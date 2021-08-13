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

local line_width <const> = 78
local rule_kwargs <const> = {
	'description',
	'generator',
	'pool',
	'restat',
	'rspfile',
	'rspfile_content',
	'deps',
	'depfile',
}
local rule_bool_kwargs <const> = {
	['generator'] = true,
	['restat'] = true,
}

local function isblank(obj)
	return obj == nil or (type(obj) == 'string' and strmatch(obj, '^%s*$') ~= nil)
end

local function as_list_(input, output)
	if isblank(input) then
	elseif type(input) == 'table' and getmetatable(input) == nil then
		for _, item in ipairs(input) do
			as_list_(item, output)
		end
	else
		output[#output+1] = tostring(input)
	end
end

local function as_list(input)
	local output = {}
	as_list_(input, output)
	return output
end

local function escape_path(word)
	return word:gsub('%$ ', '$$ '):gsub(' ', '$ '):gsub(':', '$:')
end

local function append_path(list, t)
	for _, v in ipairs(t) do
		list[#list+1] = escape_path(v)
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

function ninja.Writer(filename)
	local w = {}
	local output = {}
	local function write(text)
		output[#output+1] = text
		output[#output+1] = "\n"
	end
	local function writeline(text, indent)
		indent = indent or 0
		local leading = strrep('  ', indent)
		local targetlen = line_width - #leading
		while #text + #leading > line_width do
			local available = targetlen - 2 -- #' $'
			local space =  nextwrap(text, available)
			if space < 1 then
				space = wrapafter(text, available)
			end
			if space < 1 then
				break
			end
			write(leading .. substr(text, 1, space - 1) .. ' $')
			text = substr(text, space + 1)
			leading = strrep('  ', indent+2)
			targetlen = line_width - #leading
		end
		write(leading .. text)
	end
	function w:comment(text)
		local linewidth = line_width - 2
		local idx = nextwrap(text, linewidth)
		while idx > 1 do
			write('# ' .. substr(text, 1, idx - 1))
			text = substr(text, idx + 1)
			idx = nextwrap(text, linewidth)
		end
		write('# ' .. text)
	end
	function w:variable(key, value, indent)
		if isblank(value) then return end
		writeline(strfmt('%s = %s', key, value), indent)
	end
	function w:pool(name, depth)
		writeline('pool ' .. name)
		self:variable('depth', depth, 1)
	end
	function w:rule(name, command, kwargs)
		writeline('rule '.. name)
		self:variable('command', command, 1)
		if kwargs then
			for _, key in ipairs(rule_kwargs) do
				if kwargs[key] then
					if rule_bool_kwargs[key] then
						self:variable(key, '1', 1)
					else
						self:variable(key, kwargs[key], 1)
					end
				end
			end
		end
	end
	function w:build(outputs, rule, inputs, implicit, order_only, variables,implicit_outputs)
		local all_inputs = {}
		local all_outputs = {}
		append_path(all_inputs, as_list(inputs))
		append_path(all_outputs, as_list(outputs))
		if implicit then
			local t = as_list(implicit)
			if #t > 0 then
				all_inputs[#all_inputs+1] = "|"
				append_path(all_inputs, t)
			end
		end
		if order_only then
			local t = as_list(order_only)
			if #t > 0 then
				all_inputs[#all_inputs+1] = "||"
				append_path(all_inputs, t)
			end
		end
		if implicit_outputs then
			local t = as_list(implicit_outputs)
			if #t > 0 then
				all_outputs[#all_outputs+1] = "|"
				append_path(all_outputs, t)
			end
		end
		writeline(strfmt('build %s: %s %s', join(all_outputs), rule, join(all_inputs)))
		if variables then
			for key, value in pairs(variables) do
				self:variable(key, value, 1)
			end
		end
	end
	function w:include(path, raw)
		if not raw then path = escape_path(path) end
		writeline('include ' .. path)
	end
	function w:subninja(path, raw)
		if not raw then path = escape_path(path) end
		writeline('subninja ' .. path)
	end
	function w:default(targets)
		writeline('default ' .. join(as_list(targets)))
	end
	function w:close()
		local f <close> = assert(open(filename, 'wb'))
		f:write(tconcat(output))
	end
	return w
end

return ninja
