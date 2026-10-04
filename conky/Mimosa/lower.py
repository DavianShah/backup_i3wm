import sys
from Xlib import display, X
d = display.Display()
w = d.create_resource_object('window', int(sys.argv[1]))
w.configure(stack_mode=X.Below)
d.sync()
