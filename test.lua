
require "lutem"


tmpl = lutem:new()
ret = tmpl:load("test.tmpl")
if ret == 0 then
	result = tmpl:render({ users={"u1", "u2", "u3"}, avalue=1234, tbl={f="fieldval"} })	
	print(result)
else
	print "unable to open test.tmpl"
end
