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

-- precompil block type
local BTYPE_RAW = 0
local BTYPE_INSTR = 1
local BTYPE_EXPR = 2

-- lutem state
local LUTEM_LOADED = 1
local LUTEM_COMPILED = 2

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
	pblock_ = ltm_stack:new()
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
				end
				self.pblock_:push({lno_=k, type_=btype, content_=content})
				break
			end
		end
	end
	self.state_ = LUTEM_COMPILED
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
		table.insert(self.srclines_, line)
	end
	f:close()
	self.state_ = LUTEM_LOADED
	return 0
end

local function get_val(args, field)
	s = ""
	val = nil
	flist = {}
	for k in string.gmatch(field, "%w+") do 
		table.insert(flist, k)
	end
	
	tbl = args
	for k,v in ipairs(flist) do
		val = tbl[v]
		if val == nil then return "" end
		tbl = val
	end

	if val == nil or type(val) == "table" then return "" end
	return tostring(val)
end

function lutem:render(args, keep_custom)
	if self.state_ ~= LUTEM_LOADED then
		return "", -1
	end
	
	if self.state_ ~= LUTEM_COMPILED then self:precompile() end

	local ps = ltm_stack:new()
	local output_block = {}
	local cur_state = ST_ROOT
	--begin parse
	for k,v in pairs(self.pblock_.data_) do
		if cur_state == ST_ROOT then
			if v.type_ == BTYPE_RAW then
				table.insert(output_block, {v.lno_, v.content_})
			elseif v.type_ == BTYPE_EXPR then
				ct = get_val(args, v.content_)
				table.insert(output_block, {v.lno_, ct})
			elseif v.type_ == BTYPE_INSTR then
				--warning: not finish yet
				table.insert(output_block, {v.lno_, v.content_})
			else
				return "", -1
			end
			
		elseif cur_state == ST_IN_LOOP then
			a = nil
		end
	end

	local lno = -1
	local sline = ""
	--output block {} 1 for line no, 2 for content
	for k,v in ipairs(output_block) do
		if lno == -1 or lno ~= v[1] then
			sline = v[2]
			lno = v[1]
		else
			sline = sline .. v[2]
		end

		self.output_lines_[lno] = sline
	end	
	return table.concat(self.output_lines_, "\n"), 0
end

