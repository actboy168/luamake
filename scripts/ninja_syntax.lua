local open = io.open
local assert = assert
local type = type
local tostring = tostring
local ipairs = ipairs
local pairs = pairs
local getmetatable = getmetatable
local tconcat = table.concat
local strmatch = string.match
local strfind = string.find
local substr = string.sub

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

local function is_even_dollars_before_index(str, index)
	local count = 0
	index = index - 1
	while index > 1 and substr(str, index, index) == '$' do
		count = count + 1
		index = index - 1
	end
	return count % 2 == 0
end

local function nextwrap(text, start, count)
	local truncd = substr(text, start, start + count - 1)
	local found = strfind(truncd, '%s+[^%s]*$')
	if found == nil then return end
	if is_even_dollars_before_index(truncd, found) then
		return start + found - 1
	end
	return nextwrap(text, start, found-1)
end

local function wrapafter(text, start)
	local found = strfind(text, '%s+', start)
	if found == nil then return end
	if is_even_dollars_before_index(text, found) then
		return found
	end
	return wrapafter(text, found+1)
end

local function findwrap(text, start, count)
	if #text < start + count then
		return
	end
	local found = nextwrap(text, start, count)
	if found then
		return found
	end
	return wrapafter(text, start + count)
end

return function (filename)
	local w = {}
	local output = {}
	local function write(text)
		output[#output+1] = text
		output[#output+1] = "\n"
	end
	local function writeline(text)
		local start
		do
			local available <const> = line_width - 2 -- sizeof ' $'
			if #text <= line_width then
				write(text)
				return
			end
			local found = findwrap(text, 1, available)
			if not found then
				write(text)
				return
			end
			write(substr(text, 1, found - 1)..' $')
			start = found + 1
		end
		local leading <const> = '    '
		local available <const> = line_width - 4 - 2
		while #text > start + line_width - 5 do
			local found = findwrap(text, start, available)
			if not found then
				break
			end
			write(leading..substr(text, start, found - 1)..' $')
			start = found + 1
		end
		write(leading..substr(text, start))
	end
	local function block_variable(key, value)
		if isblank(value) then return end
		writeline('  '..key..' = '..value)
	end
	function w:variable(key, value)
		if isblank(value) then return end
		writeline(key..' = '..value)
	end
	function w:comment(text)
		local available = line_width - 2
		local start = 1
		local found = findwrap(text, start, available)
		while found do
			write('# ' .. substr(text, start, found - 1))
			start = found + 1
			found = findwrap(text, start, available)
		end
		write('# ' .. text)
	end
	function w:pool(name, depth)
		writeline('pool ' .. name)
		block_variable('depth', depth)
	end
	function w:rule(name, command, kwargs)
		writeline('rule '.. name)
		block_variable('command', command)
		if kwargs then
			for _, key in ipairs(rule_kwargs) do
				if kwargs[key] then
					if rule_bool_kwargs[key] then
						block_variable(key, '1')
					else
						block_variable(key, kwargs[key])
					end
				end
			end
		end
	end
	function w:build(outputs, rule, inputs, args)
		local s = {"build"}
		append_path(s, as_list(outputs))
		if args and args.implicit_outputs then
			local t = as_list(args.implicit_outputs)
			if #t > 0 then
				s[#s+1] = "|"
				append_path(s, t)
			end
		end
		s[#s] = s[#s]..":"
		s[#s+1] = rule
		append_path(s, as_list(inputs))
		if args and args.implicit_inputs then
			local t = as_list(args.implicit_inputs)
			if #t > 0 then
				s[#s+1] = "|"
				append_path(s, t)
			end
		end
		if args and args.order_only then
			local t = as_list(args.order_only)
			if #t > 0 then
				s[#s+1] = "||"
				append_path(s, t)
			end
		end
		writeline(join(s))
		if args and args.variables then
			for key, value in pairs(args.variables) do
				block_variable(key, value)
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
