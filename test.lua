
require "lutem_new"


tmpl = lutem:new()
ret = tmpl:load("test.tmpl")
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
	print "unable to open test.tmpl"
end
