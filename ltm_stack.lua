-- parser stack for lutem

ltm_stack = {
	top_ = -1,
	data_ = {},
}

function ltm_stack:push(v)
	if self.top_ == -1 then
		self.top_ = 1
	else
		self.top_ = self.top_ + 1
	end
	self.data_[self.top_] = v
end

function ltm_stack:size()
	if self.top_ == -1 then
		return 0
	else
		return self.top_
	end
end

function ltm_stack:pop()
	if self.top_ == -1 then return nil end
	
	v = self.data_[self.top_]
	table.remove(self.data_, self.top_)
	self.top_ = self.top_ - 1
	return v
end

function ltm_stack:top()
	if self.top_ == -1 then return nil end
	return self.data_[self.top_]
end

function ltm_stack:new(o)
	o = o or {top_ = -1, data_ = {}}
	setmetatable(o, self)
	self.__index = self
	return o
end


