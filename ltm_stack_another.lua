-- parser stack for lutem

ltm_stack = { }

function ltm_stack:push(v)
	table.insert(self.data_, v)
end

function ltm_stack:size()
	return #self.data_
end

function ltm_stack:pop()
	return table.remove(self.data_)
end

function ltm_stack:top()
	return self.data_[#self.data_]
end

function ltm_stack:new()
        o = {data_={}} 
        setmetatable(o, self)
        self.__index = self
        return o
end
