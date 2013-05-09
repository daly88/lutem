
require "lutem"


tmpl = lutem:new()
ret,errmsg = tmpl:load("test_sub.tmpl", "./")
args = {}
args.bigul = {1,2,3}
args.users = {
	{username="linlu", url="/#1"}, 
	{username="zhi2", url="/#2"},
	{username="daly", url="/#3"} 
}
args.css= {color="\"color:red\""}
if ret == 0 then
	result = tmpl:render(args)	
	print(result)
else
	print(errmsg)
end

tmp2 = lutem:new()
ret,errmsg = tmp2:load("test.tmpl")
if ret == 0 then print(tmp2:render(args)) end
