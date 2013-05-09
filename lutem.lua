-- lutem - lua template engine
-- @Copyright  Daly
--

--node type define
local NODE_TEXT = 1
local NODE_FOR = 2
local NODE_EXPR = 3
local NODE_BLOCK = 4
local NODE_RAW = 5

ast_node = {
	node_type = NODE_BLOCK, 
	child_ = {},
	parent_ = nil,

	lno_ = 0,     --start line no 
	content = "", --raw content, different nodes has different meaning
}

lutem = {
	output_ = {},     --render output buffer
	state_ = 0,      --finish parsing or not
	args_ = {},

	lineno_ = 0,    --line count
	node_root_ = nil,     --block
	blocks_ = {},

	involve_file_ = {}, 
	file_queue_ = {},   --inherit by extends
	path_root_ = "./",
}


--utils
local function obj_copy(t1)
	local tb = {}
	for k,v in pairs(t1) do 
		if type(v) == "table" then 
			tb[k] = obj_copy(v) 
		else	
			tb[k] = v 
		end
	end
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
	local o = {}
	o.output_ = {}   
	o.args_ = {}
	o.node_root_ = nil  
	o.blocks_ = {}
	o.involve_file_ = {} 
	o.file_queue_ = {} 

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
	elseif cmd == "extend" or cmd == "block" then
		--only 1 param
		if nf > 2 then return "",{} end 
		table.insert(arglist, arr_token[2])
	end
	return cmd, arglist
end

local function print_node(node, prefix)
	if node.node_type == NODE_FOR then
		print(prefix .. " " .. node.content[2])
	else 
		print(prefix .. " " .. node.content)
	end
end

function lutem:parse_file(filename, path)
	srclines = {}
	local f, err = io.open(self.path_root_..filename, 'r')
	if f == nil then return -1,"parse file error "..filename  end

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
	local pos_s, pos_e, pos_tmp
	local last = 1
	local i,j
	local bstack = {}  --block / for stack 
	local pre, word, cmd, arglist 
	local skip_block = 0
	table.insert(bstack, cur_parent)
	for lno,text in ipairs(srclines) do
		while (last <= #text) do
			--skip extended block
			if skip_block == 1 then 
				i, j = string.find(text, "{%%[ ]*endblock[ ]*%%}", last)
				if i == nil then 
					break 
				else
					last = i
				end
			end

			pos_s = string.find(text, "{[{%%]", last)
			if pos_s == nil then

				if #(cur_text.content) < 1000 then
					cur_text.content = cur_text.content .. string.sub(text, last)
				else 
					table.insert(cur_parent.child_, cur_text)	
					cur_text = new_ast_node(NODE_TEXT, cur_parent, string.sub(text, last))
				end 
				break
			end 

			--while found {{ or {%
			
			cur_text.content = cur_text.content .. string.sub(text, last, pos_s-1)
			table.insert(cur_parent.child_, cur_text)	
			cur_text = new_ast_node(NODE_TEXT, cur_parent, "")
			pre = string.sub(text, pos_s, pos_s + 1)
			last = pos_s + 2
			if pre == '{{' then
				i, j = string.find(text, "[ ]*'[^']+'[ ]*}}", last)
				if i == last then
					word = string.match(text, "'[^']+'", i, j-2)	
					node = new_ast_node(NODE_RAW, cur_parent, string.sub(word, 2, -2))
				else
					i, j = string.find(text, "[ ]*[%w._]+[ ]*}}", last) 
					if i ~= last then return -1, "expr error: "..cur_lno end
					word = string.match(text, "[%w._]+", i, j-2)
					node = new_ast_node(NODE_EXPR, cur_parent, word)
				end
				last = j + 1
				table.insert(cur_parent.child_, node)
			else
				-- parse command
				i, j = string.find(text, "[%w/._%- ]+%%}", last) 
				if i ~= last then return -1, "command error "..cur_lno end
				cmd, arglist = parse_instr(string.sub(text, i, j-2))
				if cmd == "" then return -1, "command syntax error "..cur_lno end
				last = j + 1

				if cmd == "for" then
					node = new_ast_node(NODE_FOR, cur_parent, arglist)
					table.insert(cur_parent.child_, node)
					cur_parent = node
					table.insert(bstack, node)

				elseif cmd == "endfor" then
					if #bstack < 1 or bstack[#bstack].node_type ~= NODE_FOR then
						return -1, "endfor syntax error "..cur_lno 
					end
					table.remove(bstack)	
					cur_parent = bstack[#bstack]
				elseif cmd == "block" then
					if self.blocks_[arglist[1]] ~= nil then
						node = self.blocks_[arglist[1]]
						skip_block = 1
					else
						node = new_ast_node(NODE_BLOCK, cur_parent, arglist[1])
						self.blocks_[arglist[1]] = node
					end
					table.insert(cur_parent.child_, node)
					cur_parent = node
					table.insert(bstack, node)
				elseif cmd == "endblock" then
					if #bstack < 1 or bstack[#bstack].node_type ~= NODE_BLOCK then
						return -1, "endblock error: "..cur_lno
					end
					table.remove(bstack)
					cur_parent = bstack[#bstack]
					skip_block = 0
				elseif cmd == "extend" then
					if self.involved_file ~= nil then
						return -1, "extend duplicated: "..cur_lno
					end 
					if cur_parent.content ~= "__root"
						or #cur_parent.child_ > 2
						or #bstack > 1 then
						return -1, "extend error: "..cur_lno
					end

					table.insert(self.file_queue_, arglist[1])
				end
			end

		--end while
		end

		cur_lno = cur_lno + 1
		last = 1
	end

	table.insert(cur_parent.child_, cur_text)	
	if #bstack > 1 then return -1, print_node(bstack[#bstack], "unmatch block") end
	return 0
end


function lutem:load(filename, path)
	self.involve_file_[filename] = 1
	self.path_root_ = path
	table.insert(self.file_queue_, filename)
	self.queue_pos_ = 1
	while self.queue_pos_ <= #self.file_queue_ do
		local ret,reason = self:parse_file(self.file_queue_[self.queue_pos_])
		if ret == -1 then 
			return -1,reason
		end
		self.queue_pos_ = self.queue_pos_ + 1	
	end
	self.state = 1	
	return 0
end

-- get expression value.
-- support plain variable or table field access
-- Example: {{ varname }}, {{ tbl.sub.field }}
function lutem:get_expr_val(expr)
	local flist = {}
	--table field split by .  e.g:  xxx.yyy.zzz
	for k in string.gmatch(expr, "[%w_]+") do
		table.insert(flist, k)
	end
	-- plain variable
	if #flist == 1 then
		if self.args_[expr] == nil then return "" end
		return tostring(self.args_[expr]) 
	end
	-- table field access
	local val = nil
	local tbl = self.args_
	for _, v in ipairs(flist) do
		if type(tbl) ~= "table" then return "" end
		val = tbl[v]
		if val == nil then return "" end
		tbl = val
	end
	if val == nil or type(val) == "table" then return "" end
	return tostring(val)	
end

function lutem:render_block(block)
	for _, node in ipairs(block.child_) do
		if node.node_type == NODE_TEXT or node.node_type == NODE_RAW then
			self.output_ = self.output_  .. node.content
		elseif node.node_type == NODE_EXPR then
			self.output_ = self.output_ .. self:get_expr_val(node.content)
		elseif node.node_type == NODE_BLOCK then
			self:render_block(node)
		elseif node.node_type == NODE_FOR then
			self:render_loop(node)
		else
			self.output_ = self.output_ .. node.content
		end
	end
end

function lutem:render_loop(block)
	iter_tbl = {}
	kname = block.content[1]
	vname = block.content[1]
	tbl_name = block.content[2]
	for k, v in ipairs(self.args_[tbl_name]) do
		table.insert(iter_tbl, {key=k, val=v})
	end
	
	for _, elem in ipairs(iter_tbl) do 
		self.args_[kname] = elem.key
		self.args_[vname] = elem.val
		for _, node in ipairs(block.child_) do
			if node.node_type == NODE_TEXT then
				self.output_ = self.output_ .. node.content
			elseif node.node_type == NODE_EXPR then
				self.output_ = self.output_ .. self:get_expr_val(node.content)
			elseif node.node_type == NODE_FOR then
				self:render_loop(node)
			else
				self.output_ = self.output_ .. node.content
			end
		end
	end
end

function lutem:render(args)
	if self.state ~= 1 then return "", -1 end
	self.output_ = ""	
	self.args_ = args
	self:render_block(self.node_root_)
	return self.output_
end


return lutem
