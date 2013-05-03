-- lutem - lua template engine
-- @Copyright  Daly
--

--node type define
local NODE_TEXT = 1
local NODE_FOR = 2
local NODE_EXPR = 3
local NODE_BLOCK = 4
local NODE_RAW = 5

--lex token string
local INSTR_EXTEND = "extends"
local INSTR_START = "{%"
local INSTR_END = "%}"

local ast_node = {
	node_type = NODE_BLOCK, 
	child_ = {},
	parent_ = nil,

	lno_ = 0,     --start line no 
	content = "", --raw content, different nodes has different meaning
}

lutem = {
	output_ = {},     --render output buffer
	args_ = {},       --template variable 

	lineno_ = 0,    --line count
	node_root_ = nil,     --block
	blocks_ = {},
	inherit_from_ = {},   --inherit by extends
}


--utils
local function obj_copy(t1)
	tb = {}
	for k,v in pairs(t1) do tb[k] = v end
	return tb
end

local function new_ast_node(ntype, parent, content)
	tb = obj_copy(ast_node)
	tb.parent_ = parent
	tb.node_type = ntype
	tb.content = content
	return tb
end

function lutem:new()
	o = {}
	setmetatable(o, self)
	self.__index = self
	return o
end

-- parse command in {% %}
-- return: (cmd, arglist)
-- 	  cmd --  command name
-- 	  arglist -- an array of arglist(according to command)
local function parse_instr(s)
	local nf = 0
	local cmd = nil
	local arglist = {}	
	local arr_token = {}
	for f in string.gmatch(s, "([^ \t\r\n]+)") do
		table.insert(arr_token, f)
		nf = nf + 1
	end
	--check token
	if nf < 1 then return "", -1 end
	cmd = arr_token[1]
	if cmd == "for" then
		if nf ~= 4 and nf ~= 5 then return "",{} end
		if arr_token[nf-1] ~= "in" then return "",{} end
		if nf == 5 then 
			--maybe has space between iter key and value, join them
			table.insert(arglist, arr_token[2]..arr_token[3])
		else 
			table.insert(arglist, arr_token[2])
		end

		table.insert(arglist, arr_token[nf])
	elseif cmd == "endfor" or cmd == "endblock" then
		--no param
		if nf > 1 then return "",{} end
	elseif cmd == "include" or cmd == "extend" or cmd == "block" then
		--only 1 param
		if nf > 2 then return "",{} end 
		table.insert(arglist, arr_token[2])
	end
	return cmd, arglist
end

function lutem:readfile(filename)
	srclines = {}
	local f, err = io.open(filename, 'r')
	if f == nil then return -1,0,0 end

	for line in f:lines() do
		table.insert(srclines, line .. "\n")
	end
	f:close()

	--compile it
	local node = nil
	local extend_from = nil
	local cur_block = new_ast_node(NODE_BLOCK, nil, "__root")
	local cur_parent = cur_block
	local cur_text = new_ast_node(NODE_TEXT, cur_parent, "")
	--self.blocks_["__root"] = cur_parent
	self.node_root_ = cur_parent
	
	local cur_lno = 1
	local lex_bstart = '{[{%%]'
	local pos_s, pos_e, pos_tmp, last
	local i,j
	local bstack = {}  --block / for stack 
	local pre, word, cmd, arglist 

	for lno,text in ipairs(srclines) do
		while (last < #text) do
			pos_s = string.find(text, "{[{%%]", last)
			if pos_s == nil then
				if #(cur_text.content) < 1000 then
					cur_text.content = cur_text.content .. string.sub(text, last)
				else 
					table.insert(cur_parent.child, cur_text)	
					cur_text = new_ast_node(NODE_TEXT, cur_parent, "")
				end 
				break
			end 

			--while found {{ or {%
			
			if #(cur_text.content) > 0 then
				table.insert(cur_parent.child, cur_text)	
				cur_text = new_ast_node(NODE_TEXT, cur_parent, "")
			end 
			pre = string.sub(text, pos_s, pos_s + 2)
			last = last + 2
			if pre == '{{' then
				i, j = string.find(text, "[ ]*[%w_]+[ ]*}}", last) 
				if i ~= last then return -1, cur_lno, last end
				last = j + 1
				word = string.match(text, "[%w_]+", i, j-2)
				node = new_ast_node(NODE_EXPR, cur_parent, word)
				table.insert(cur_parent.child, node)
			else
				-- parse command
				i, j = string.find(text, "[ ]*[%w_]+[ ]*%%}", last) 
				if i ~= last then return -1, cur_lno, last end
				cmd, arglist = parse_instr(string.sub(text, i, j-2))
				if cmd == "" then return -1, cur_lno, last end
				last = j + 1

				if cmd == "for" then
					node = new_ast_node(NODE_FOR, cur_parent, arglist)
					cur_parent = node
					table.insert(bstack, node)
				elseif cmd == "endfor" then
					if #bstack < 1 or bstack[#bstack].node_type ~= NODE_FOR then
						return -1, cur_lno, last
					end
					table.remove(bstack)	
					cur_parent = bstack[#bstack]
				elseif cmd == "block" then
					node = new_ast_node(NODE_BLOCK, cur_parent, arglist[1])
					cur_parent = node
					table.insert(bstack, node)
					if self.blocks_[arglist[1]] == nil then
						self.blocks_[arglist[1]] = node
					end
				elseif cmd == "endblock" then
					if #bstack < 1 or bstack[#bstack].node_type ~= NODE_BLOCK then
						return -1, cur_lno, last
					end
					table.remove(bstack)
					cur_parent = bstack[#bstack]
				elseif cmd == "extend" then
					if cur_parent.content ~= "__root"
						or #cur_parent.child > 2
						or #bstack > 0 then
						return -1, cur_lno, last	
					end

					table.insert(self.inherit_from_, arglist[1])
				end
			end

		--end while
		end

		cur_lno = cur_lno + 1
		last = 1
	end

	return 0
end

