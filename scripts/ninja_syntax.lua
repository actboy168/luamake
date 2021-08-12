local open = io.open
local assert = assert
local type = type
local tostring = tostring
local ipairs = ipairs
local pairs = pairs
local tconcat = table.concat
local strmatch = string.match
local strfind = string.find
local substr = string.sub
local strrep = string.rep
local strfmt = string.format

local ninja = {}

local function isblank(obj)
	return obj == nil or (type(obj) == 'string' and strmatch(obj, '^%s*$') ~= nil)
end

function ninja.escape(str)
	assert(str, 'str cannot be nil!')
	assert(not strfind(str, '\n', 1, true), 'Ninja syntax does not allow newlines')
	return str:gsub('%$', '$$')
end

function ninja.expand(str, vars, locals)
	vars = vars or {}
	locals = locals or {}
	local function expand(varname)
		return locals[varname] or vars[varname] or ('$'..varname)
	end
	return str:gsub('%$([%w_]*)', expand):gsub('%$([%$:%s])', '%1')
end

local function as_list(input, output)
	if isblank(input) then
	elseif type(input) == 'table' and getmetatable(input) == nil then
		for _, item in ipairs(input) do
			as_list(item, output)
		end
	else
		output[#output+1] = tostring(input)
	end
end

function ninja.as_list(input)
	local output = {}
	as_list(input, output)
	return output
end

function ninja.escape_path(word)
	return word:gsub('%$ ', '$$ '):gsub(' ', '$ '):gsub(':', '$:')
end

ninja.DEFAULT_LINE_WIDTH = 78

local function append_path(list, t)
	for _, v in ipairs(t) do
		list[#list+1] = ninja.escape_path(v)
	end
end

local function join(list)
	return tconcat(list, ' ')
end

local function is_event_dollars_before_index(str, index)
	local count = 0
	index = index - 1
	while index > 1 and substr(str, index, index) == '$' do
		count = count + 1
		index = index - 1
	end
	return count % 2 == 0
end

local function nextwrap(text, width)
	if #text <= width then return 0 end
	local truncd = substr(text, 1, width)
	local foundws = { strfind(truncd, '^.*()(%s+).*$') }
	if foundws[3] == nil then return 0 end
	local index = foundws[3]
	if is_event_dollars_before_index(truncd, index) then
		return index
	end
	return nextwrap(text, index-1)
end

local function wrapafter(text, index)
	local index = strfind(text, '%s+', index)
	if index == nil then return 0 end
	if is_event_dollars_before_index(text, index) then
		return index
	end
	return wrapafter(text, index+1)
end

local Writer = {}
Writer.__index = Writer

function Writer:comment(text)
	local linewidth = self.width - 2
	local idx = nextwrap(text, linewidth)
	while idx > 1 do
		self:_writeline('# ' .. substr(text, 1, idx - 1))
		text = substr(text, idx + 1)
		idx = nextwrap(text, linewidth)
	end
	self:_writeline('# ' .. text)
end

function Writer:variable(key, value, indent)
	if isblank(value) then return end
	self:line(strfmt('%s = %s', key, value), indent)
end

function Writer:pool(name, depth)
	self:line('pool ' .. name)
	self:variable('depth', depth, 1)
end

local simple_kwargs <const> = {
	'description', 'depfile', 'pool', 'rspfile',
	'rspfile_content', 'deps', 'msvc_deps_prefix'
}
local bool_kwargs <const> = {
	'generator', 'restat'
}
function Writer:rule(name, command, kwargs)
	self:line('rule '.. name)
	self:variable('command', command, 1)
	if kwargs then
		for _,key in ipairs(bool_kwargs) do
			if kwargs[key] then
				self:variable(key, '1', 1)
				kwargs[key] = nil
			end
		end
		for _, key in pairs(simple_kwargs) do
			if kwargs[key] then
				self:variable(key, kwargs[key], 1)
			end
		end
	end
end

function Writer:build(outputs, rule, inputs, implicit, order_only, variables,implicit_outputs)
	local all_inputs = {}
	local all_outputs = {}
	append_path(all_inputs, ninja.as_list(inputs))
	append_path(all_outputs, ninja.as_list(outputs))
	if implicit then
		local t = ninja.as_list(implicit)
		if #t > 0 then
			all_inputs[#all_inputs+1] = "|"
			append_path(all_inputs, t)
		end
	end
	if order_only then
		local t = ninja.as_list(order_only)
		if #t > 0 then
			all_inputs[#all_inputs+1] = "||"
			append_path(all_inputs, t)
		end
	end
	if implicit_outputs then
		local t = ninja.as_list(implicit_outputs)
		if #t > 0 then
			all_outputs[#all_outputs+1] = "|"
			append_path(all_outputs, t)
		end
	end
	self:line(strfmt('build %s: %s %s', join(all_outputs), rule, join(all_inputs)))
	if variables then
		for key, value in pairs(variables) do
			self:variable(key, value, 1)
		end
	end
end

function Writer:include(path, raw)
	if not raw then path = ninja.escape_path(path) end
	self:line('include ' .. path)
end

function Writer:subninja(path, raw)
	if not raw then path = ninja.escape_path(path) end
	self:line('subninja ' .. path)
end

function Writer:default(targets)
	self:line('default ' .. join(ninja.as_list(targets)))
end

function Writer:close()
	local f <close> = assert(open(self.filename, 'wb'))
	f:write(tconcat(self.output))
end

function Writer:_writeline(text)
	self.output[#self.output+1] = text
	self.output[#self.output+1] = "\n"
end

function Writer:line(text, indent)
	indent = indent or 0
	local leading = strrep('  ', indent)
	local targetlen = self.width - #leading
	while #text + #leading > self.width do
		local available = targetlen - 2 -- #' $'
		local space =  nextwrap(text, available)
		if space < 1 then
			space = wrapafter(text, available)
		end
		if space < 1 then
			break
		end
		self:_writeline(leading .. substr(text, 1, space - 1) .. ' $')
		text = substr(text, space + 1)
		leading = strrep('  ', indent+2)
		targetlen = self.width - #leading
	end
	self:_writeline(leading .. text)
end

function ninja.Writer(filename, width)
	local w = {
		width = width or ninja.DEFAULT_LINE_WIDTH,
		output = {},
		filename = filename
	}
	return setmetatable(w, Writer)
end

return ninja
