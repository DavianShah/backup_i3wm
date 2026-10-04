/* wallpaper-embed: video wallpaper for i3 via libmpv.
 *
 * i3 manages every normal top-level window, so a player window gets tiled
 * into the layout. This helper creates an override-redirect window at the
 * bottom of the stack (i3 ignores override-redirect windows) and hands it
 * to libmpv via the wid option, so the video renders directly into the
 * wallpaper window: no child window, nothing for i3 to manage. The helper
 * owns the window for its whole lifetime and tears everything down on
 * SIGTERM/SIGINT.
 *
 * libmpv has no installed header here; the prototypes below are the stable
 * client ABI (libmpv.so.2, symbols verified with nm).
 *
 * usage: wallpaper-embed <video>
 */
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <unistd.h>

typedef struct mpv_handle mpv_handle;
typedef struct mpv_event mpv_event;
extern mpv_handle *mpv_create(void);
extern int mpv_initialize(mpv_handle *ctx);
extern int mpv_set_option_string(mpv_handle *ctx, const char *name, const char *value);
extern int mpv_command(mpv_handle *ctx, const char **args);
extern mpv_event *mpv_wait_event(mpv_handle *ctx, double timeout);
extern void mpv_terminate_destroy(mpv_handle *ctx);

static volatile sig_atomic_t stop = 0;

static void on_term(int sig)
{
	(void)sig;
	stop = 1;
}

static void opt(mpv_handle *mpv, const char *name, const char *value)
{
	int err = mpv_set_option_string(mpv, name, value);
	if (err < 0)
		fprintf(stderr, "wallpaper-embed: mpv option %s=%s rejected (%d)\n",
			name, value, err);
}

int main(int argc, char **argv)
{
	if (argc != 2) {
		fprintf(stderr, "usage: %s <video>\n", argv[0]);
		return 2;
	}

	Display *dpy = XOpenDisplay(NULL);
	if (!dpy) {
		fprintf(stderr, "wallpaper-embed: cannot open display\n");
		return 1;
	}
	int scr = DefaultScreen(dpy);
	unsigned w = (unsigned)DisplayWidth(dpy, scr);
	unsigned h = (unsigned)DisplayHeight(dpy, scr);
	Window root = RootWindow(dpy, scr);

	XSetWindowAttributes swa;
	memset(&swa, 0, sizeof swa);
	swa.override_redirect = True;
	swa.background_pixel = BlackPixel(dpy, scr);
	Window win = XCreateWindow(dpy, root, 0, 0, w, h, 0, CopyFromParent,
				  InputOutput, CopyFromParent,
				  CWOverrideRedirect | CWBackPixel, &swa);
	XStoreName(dpy, win, "wallpaper-embed");
	XMapWindow(dpy, win);
	XLowerWindow(dpy, win);
	XFlush(dpy);

	char wid[32];
	snprintf(wid, sizeof wid, "%lu", (unsigned long)win);

	mpv_handle *mpv = mpv_create();
	if (!mpv) {
		fprintf(stderr, "wallpaper-embed: mpv_create failed\n");
		return 1;
	}
	opt(mpv, "wid", wid);
	opt(mpv, "terminal", "yes");
	opt(mpv, "msg-level", "all=warn");
	opt(mpv, "loop-file", "inf");
	opt(mpv, "hwdec", "no");
	opt(mpv, "panscan", "1.0");
	opt(mpv, "osc", "no");
	opt(mpv, "osd-level", "0");
	if (mpv_set_option_string(mpv, "aid", "no") < 0)
		opt(mpv, "ao", "null");

	int err = mpv_initialize(mpv);
	if (err < 0) {
		fprintf(stderr, "wallpaper-embed: mpv_initialize failed (%d)\n", err);
		return 1;
	}
	const char *cmd[] = {"loadfile", argv[1], NULL};
	err = mpv_command(mpv, cmd);
	if (err < 0) {
		fprintf(stderr, "wallpaper-embed: loadfile failed (%d)\n", err);
		return 1;
	}

	signal(SIGTERM, on_term);
	signal(SIGINT, on_term);

	int xfd = ConnectionNumber(dpy);
	while (!stop) {
		XLowerWindow(dpy, win);

		/* Drain X events; then up to 32 immediate mpv events (no
		 * struct access needed — the queue is just consumed). */
		fd_set fds;
		FD_ZERO(&fds);
		FD_SET(xfd, &fds);
		struct timeval tv = {0, 200000};
		if (select(xfd + 1, &fds, NULL, NULL, &tv) > 0) {
			while (XPending(dpy)) {
				XEvent ev;
				XNextEvent(dpy, &ev);
			}
		}
		for (int i = 0; i < 32; i++)
			mpv_wait_event(mpv, 0.0);
	}

	mpv_terminate_destroy(mpv);
	XDestroyWindow(dpy, win);
	XCloseDisplay(dpy);
	return 0;
}
