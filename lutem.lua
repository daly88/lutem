-- lutem - lua template engine
-- @License MIT license
-- @Copyright  Daly
--

--lutem class define

require "ltm_stack"

-- parser state definition
local ST_ROOT = 0
local ST_IN_LOOP = 1
local ST_IN_BLOCK = 2

-- precompile block type
local BTYPE_RAW = 0
local BTYPE_INSTR = 1
local BTYPE_EXPR = 2

lutem = {
	srclines_ = {},  --template source lines(key by lineno)
	output_lines_ = {},  -- render output buffer
	args_ = {},    -- template variable
	filename_ = "",

	begin_custom_ = "",
	stop_custom_ = "",
	keep_custom = 0,

	lineno_ = 0,
	block_ = 0,
	state_ = 0,   -- lutem state
	is_inherit_ = 0,
	pblock_ = ltm_stack:new(),
	pstack_ = ltm_stack:new()
}


function lutem:precompile()
	if self.filename_ == "" then return end

	for k,v in ipairs(self.srclines_) do
		self.pblock_:push({lno_=k, type_=BTYPE_RAW, content_=""})
		for text, block in string.gmatch(v.."{___}", "([^{]-)(%b{})") do
			if text:len() > 0 then
				self.pblock_:push({lno_=k, type_=BTYPE_RAW, content_=text})
			end

			while block ~= "{___}" do
				if block:len() < 4 then
					self.pblock_:push({lno_=k, type_=BTYPE_RAW, content_=block})
					break
				end

				btype = BTYPE_RAW
				content = block
				head_tag = block:sub(1,2)
				tail_tag = block:sub(-2)
				if head_tag == "{%" and tail_tag == "%}" then
					btype = BTYPE_INSTR
					content = content:sub(3,-3)
				elseif head_tag == "{=" and tail_tag == "=}" then 
					btype = BTYPE_EXPR
					content = content:sub(3,-3)
					-- strip it
					content = string.gsub(content, "^[ ]+", "")
					content = string.gsub(content, "[ ]+$", "")
				end
				self.pblock_:push({lno_=k, type_=btype, content_=content})
				break
			end
		end
	end
end


--inteface--------------------------------

-- new a lutem manager ------------------
function lutem:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end


-- load template file -------------------
function lutem:load(filename)
	self.filename_ = filename
	local f, err = io.open(filename, 'r')
	if f == nil then return -1 end

	for line in f:lines() do
		table.insert(self.srclines_, line .. "\n")
	end
	f:close()
	self:precompile()
	self.state_ = 1 
	return 0
end

local function copy_table(t1)
	tb = {}
	for k,v in pairs(t1) do tb[k] = v end
	return tb
end

local function get_field_val(args, field)
	local s = ""
	local val = nil
	local flist = {}

	for k in string.gmatch(field, "%w+") do 
		table.insert(flist, k)
	end
	
	local tbl = args
	if tbl == nil then return "" end

	for k,v in ipairs(flist) do
		val = tbl[v]
		if val == nil then return "" end
		tbl = val
	end

	if val == nil or type(val) == "table" then return "" end
	return tostring(val)
end

-- parse command in {% %}
-- return: (cmd, arglist)
-- 	  cmd --  command name
-- 	  arglist -- an array of arglist(according to command)
local function parse_instr(s)
	local nf = 0
	local cmd = nil
	local arglist = {}	
	for f in string.gmatch(s, "([^ \t]+)") do
		nf = nf + 1
		while true do 
			if nf == 1 then
				cmd = f
			else
				if cmd == "for" and nf == 3 then break end
				table.insert(arglist, f)
			end
			break
		end
	end
	return cmd, arglist
end

local function new_parse_node(depth)
	o = {}
	o.content = {}
	o.depth = depth
	o.args = {}
	o.start_pc = 0
	o.iter_table = {}
	o.iter_p = 1
	o.iter_key = nil
	o.iter_val = nil
	return o
end

function lutem:parse()
	local node = nil
	local btype = 0
	local content = ""
	--begin parse
	local pc = 1  --index of current block 
	while self.pblock_.data_[pc] ~= nil do
		v = self.pblock_.data_[pc]		
		node = self.pstack_:top()
		if v.type_ == BTYPE_RAW then
			table.insert(node.content, v.content_)
			pc = pc + 1
		elseif v.type_ == BTYPE_EXPR then
			ct = get_field_val(node.args, v.content_)
			table.insert(node.content, ct)
			pc = pc + 1
		elseif v.type_ == BTYPE_INSTR then
			--warning: not finish yet
			cmd, arglist = parse_instr(v.content_)
			if cmd == nil then 
				return nil 
			end
			--do command
			if cmd == "for" then
				child_node = new_parse_node(node.depth + 1)
				kname = arglist[1]
				tb_val = node.args[arglist[2]]
				child_node.args = copy_table(node.args)
				child_node.start_pc = pc + 1
				child_node.iter_val = kname
				if tb_val == nil then tb_val = {} end
				for it_key, it_val in pairs(tb_val) do 
					table.insert(child_node.iter_table, {key=it_key, val=it_val})
				end
				child_node.iter_p = 1
				child_node.args[kname] = child_node.iter_table[1]["val"]
				self.pstack_:push(child_node)
				pc = pc + 1
			elseif cmd == "end" then 
				if node.depth == 0 then 
					return nil 
				end -- error

				iv = node.iter_table[node.iter_p]
				if iv == nil then
					self.pstack_:pop()
					parent_node = self.pstack_:top()
					table.insert(parent_node.content, table.concat(node.content,""))
					pc = pc + 1
				else
					node.iter_p = node.iter_p + 1
					node.args[node.iter_val] = iv["val"]
					--go back to for begin
					pc = child_node.start_pc
				end
			else
				return nil  --error command
			end
		else
			return nil
		end
	end

	if self.pstack_:size() ~= 1 then
		print(self.pstack_.size())
		return nil   -- no {% end %}
	end
	node = self.pstack_:top()
	return node.content
end

function lutem:render(args, keep_custom)
	if self.state_ ~= 1 then return "", -1 end
	
	local lno = -1
	local sline = ""
	local root_node = new_parse_node(0)
	root_node.args = args
	self.pstack_:push(root_node)

	local output_block = self:parse()

	if output_block == nil then
		return "ERROR", -1
	else
		return table.concat(output_block, ""), 0
	end
end

