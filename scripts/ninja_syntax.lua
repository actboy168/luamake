------------
-- Lua module for generating .ninja files.
-- @module ninja_syntax
-- @author Charles Grunwald (Juntalis) <ch@rles.rocks>
----

-- Store used packages in locals
local io, bit = io, bit

-- Cached globals
local _s, _t = string, table
local _len = function(o) return #o end
local strmatch, strfind = _s.match, _s.find
local tinsert, tconcat, tlen = _t.insert, _t.concat, _t.maxn or _len
local strlen, substr, strrep = _s.len or _len, _s.sub, _s.rep
local unpack, pack = _G.unpack or _t.unpack, function(...)
	return {...}
end

--- Module table
local ninja = {}

-- LuaJIT's minilua does not include the math module, while
-- standard Lua does not include the bit module. As a result,
-- we end up with a few different implementations of iseven.
local iseven
if bit and bit.band then
	-- Use the bit module if available.
	iseven = function(num)
		return bit.band(num, 1) ~= 1
	end
else
	iseven = function(num)
		return num % 2 == 0
	end
end

--- Check for null and empty/whitespace string values
local function isblank(obj)
	return obj == nil or (type(obj) == 'string' and
	       strmatch(obj, '^%s*$') ~= nil)
end

--- Filter out null/blank values and convert remaining items to strings
local function filter_blanks(list)
	local values = {}                                          
	for _,item in ipairs(list) do
		-- Filter out empty strings.
		if not isblank(item) then
			tinsert(values, tostring(item))
		end
	end
	return values
end

--- Utility Functions
-- @section utility

--- String escaping.
-- Escape a string such that it can be embedded into a Ninja file without
-- further interpretation.
-- @string str input string
-- @treturn string The escaped string
function ninja.escape(str)
	assert(str, 'str cannot be nil!')
	assert(not strfind(str, '\n', 1, true),
	      'Ninja syntax does not allow newlines')
	return str:gsub('%$', '$$')
end

--- Expand Expand a string containing `vars` as Ninja would.
-- Doesn't handle the full Ninja variable syntax, but it's enough to make
-- configure.lua's use of it work.
-- @string str String to expand.
-- @tparam[opt={}] table vars "global" variables - searched if var is not found in locals
-- @tparam[opt={}] table locals "local" variables - first place searched for variables
-- @treturn string expanded string
function ninja.expand(str, vars, locals)
	vars = vars or {}
	locals = locals or {}
	local function expand(varname)
		return locals[varname] or vars[varname] or ('$'..varname)
	end
	return str:gsub('%$([%w_]*)', expand):gsub('%$([%$:%s])', '%1')
end

--- Converts `input` into a table of strings.
-- If input is a blank string or nil, an empty table will be returned. If input
-- is a single scalar value, it will be converted to a string and inserted into
-- a table. Used internally
-- @param input input value
-- @treturn table input converted to a table of strings
function ninja.as_list(input)
	if isblank(input) then
		return {}
	elseif type(input) == 'table' and getmetatable(input) == nil then
		return filter_blanks(input)
	else
		return { tostring(input) }
	end
end

--- Expanded version of `ninja.escape`. Used internally for stuff.
-- @string word text to escape
-- @treturn string escaped version of word
-- @see escape
function ninja.escape_path(word)
	return word:gsub('%$ ', '$$ '):gsub(' ', '$ '):gsub(':', '$:')
end

--- Writer Options
-- @section options

--- Default line width. (78)
ninja.DEFAULT_LINE_WIDTH = 78

--- Default consecutive blank line count. (1)
ninja.DEFAULT_BLANK_LINES = 1

do
	--- Build File Writer
	-- @section writer
	
	-- Determine whether a table is keyed (versus indexed)
	local function iskeyed(T)
		return type(next(T)) == 'string'
	end

	-- Process a list with a callback, inserting the results into target
	local function map(func, list, target)
		target = target or list
		local append = target ~= list
		for idx,item in ipairs(list) do
			if append then
				local value = func(item)
				tinsert(target, value)
			else
				target[idx] = func(item)
			end
		end
		return target
	end

	-- Python-esque list.extend implementation
	local function extend(list, ...)
		list = list or {}
		local others = pack(...)
		for _,other in pairs(others) do
			for _,item in pairs(other) do
				tinsert(list, item)
			end
		end
		return list
	end

	-- Shortcut for multiple usage.
	local function join(list)
		return tconcat(list, ' ')
	end

	-- Local declaration necessary for `nextwrap`.
	local function count_dollars_before_index(str, index)
		local count = 0
		index = index - 1
		while index > 1 and substr(str, index, index) == '$' do
			count = count + 1
			index = index - 1
		end
		return count
	end

	-- Find the right-most unescaped space to wrap on
	local function nextwrap(text, width)
		if strlen(text) <= width then return 0 end
		local truncd = substr(text, 1, width)
		local foundws = { strfind(truncd, '^.*()(%s+).*$') }
		if foundws[3] == nil then return 0 end
		
		local index = foundws[3]
		if iseven(count_dollars_before_index(truncd, index)) then
			return index
		else
			return nextwrap(text, index-1)
		end
	end
	
	-- Find the first wrappable space after `index`
	local function wrapafter(text, index)
		local index = strfind(text, '%s+', index)
		if index == nil then return 0 end
		if iseven(count_dollars_before_index(text, index)) then
			return index
		else
			return wrapafter(text, index+1)
		end
	end
	
	-- Verifies whether or not a table has implemented methods
	-- similar to the lua file object
	local function isfileimpl(obj)
		return obj.write ~= nil and obj.flush ~= nil and obj.close ~= nil
	end
	
	--- Writer Implementation
	local Writer = {}
	setmetatable(Writer, {
		__call = function (cls, ...)
			return cls.new(...)
		end,
	})

	Writer.__index = Writer

	--- Writer constructor
	-- @alias Writer
	-- @tparam string|file output filepath or file handle for output .ninja file
	-- @int[opt=78] width maximum line width for wrapping
	-- @int[opt=1] blanklines maximum consecutive blank lines
	function Writer.new(output, width, blanklines)
		local self = setmetatable({}, Writer)

		-- Setup writer options
		self.width = width or ninja.DEFAULT_LINE_WIDTH
		self.blanklines = blanklines or ninja.DEFAULT_BLANK_LINES

		-- Setup writer output
		local outtype = type(output)
		if outtype == 'string' then
			self.output = assert(io.open(output, 'w'))
		elseif self:_isfile(output) then
			self.output = output
		else
			error([[Don't know how to handle type: ]] .. outtype)
		end

		-- Setup private state data
		self._P = {
			lineblank = true,
			blankscount = 0,
		}

		-- Return instance
		return self
	end

	--- Outputs a newline.
	-- Blank lines are limited to the writer's blanklines field if said
	-- field is non-zero.
	-- @treturn Writer returns self
	function Writer:newline()
		if self.blanklines > 0 then
			if self._P.lineblank then
				if self._P.blankscount >= self.blanklines then
					return
				end
				self._P.blankscount = self._P.blankscount + 1
			else
				self._P.blankscount = 0
			end
		end
		-- Chained
		return self:_write('\n', true)
	end

	--- Outputs a comment.
	-- Comment text is automatically wrapped according to the writer's width.
	-- @string text Comment text
	-- @bool[opt=false] has_path Unused - exists to maintain consistency.
	-- @treturn Writer returns self
	function Writer:comment(text, has_path)
		-- has_path doesn't appear to be used
		-- has_path = has_path or false
		local linewidth = self.width - 2
		local idx = nextwrap(text, linewidth)
		while idx > 1 do
			self:_write('# ' .. substr(text, 1, idx - 1)):newline()
			text = substr(text, idx + 1)
			idx = nextwrap(text, linewidth)
		end

		-- chain it
		return self:_write('# ' .. text):newline()
	end

	--- Define a variable to its value
	-- Blank/nil values are ignored. (and filtered from collections)
	-- @string key variable name
	-- @tparam string|number|boolean|table value variable value
	-- @int[opt=0] indent indent level
	-- @treturn Writer returns self
	function Writer:variable(key, value, indent)
		-- Handle nil values and empty strings
		if isblank(value) then return end

		-- Handle table values (lists, not dictionaries)
		if type(value) == 'table' then
			value = join(filter_blanks(value))
		end

		-- Write variable line(s) to output
		return self:_line(string.format('%s = %s', key, value), indent)
	end

	--- Pool declaration
	-- Pools allow you to allocate one or more rules or edges a finite number of
	-- concurrent jobs which is more tightly restricted than the default
	-- parallelism.
	-- @string name pool name
	-- @int depth pool depth
	-- @treturn Writer returns self
	function Writer:pool(name, depth)
		return self:_line('pool ' .. name):variable('depth', depth, 1)
	end

	--- Rule declaration
	-- Possible kwargs keys include: description, deps, depfile, pool, rspfile,
	-- rspfile_content, generator, and restat.
	-- @string name rule name
	-- @string command rule command line
	-- @tparam[opt={}] table kwargs additional optional rule configuration
	-- @treturn Writer returns self
	function Writer:rule(name, command, kwargs)
		-- Simple keyed parameters that can be passed directly to our variable
		-- method
		local simple_kwargs = { 'description', 'depfile', 'pool', 'rspfile',
		                        'rspfile_content', 'deps', 'msvc_deps_prefix' }

		-- Boolean keyed parameters that will be set to '1' if true
		local bool_kwargs = { 'generator', 'restat' }

		-- Handle mandatory parameters
		self:_line('rule '.. name)
		self:variable('command', command, 1)

		-- Handle optional keyed parameters
		if kwargs ~= nil then
			-- Boolean parameters
			for _,key in ipairs(bool_kwargs) do
				if kwargs[key] then
					self:variable(key, '1', 1)
					kwargs[key] = nil
				end
			end

			-- Simple parameters
			for _,key in pairs(simple_kwargs) do
				if kwargs[key] then
					self:variable(key, kwargs[key], 1)
				end
			end
		end

		-- chain it
		return self
	end

	--- Build statement
	-- Build statements declare a relationship between input and output files.
	-- @tparam string|table outputs output file(s)/target(s)
	-- @string rule declared rule to use
	-- @tparam string|table inputs input file(s)/target(s)
	-- @tparam ?string|table implicit implicit dependencies
	-- @tparam ?string|table order_only force build to occur after target(s)
	-- @tparam[opt] table variables any shadowed variables for this particular build
	-- @tparam[opt] table implicit_outputs no clue
	-- @treturn Writer returns self
	function Writer:build(outputs, rule, inputs, implicit, order_only,
	                      variables, implicit_outputs)
		outputs = ninja.as_list(outputs)
		local out_outputs = map(ninja.escape_path, outputs, {})
		local all_inputs = map(ninja.escape_path, ninja.as_list(inputs), { rule })

		-- Handle implicit parameter
		if implicit ~= nil then
			local t = ninja.as_list(implicit)
			if #t > 0 then
				tinsert(all_inputs, '|')
				extend(all_inputs, map(ninja.escape_path, t, {}))
			end
		end

		-- Handle order_only parameter
		if order_only ~= nil then
			local t = ninja.as_list(order_only)
			if #t > 0 then
				tinsert(all_inputs, '||')
				extend(all_inputs, t)
			end
		end

		-- Handle implicit_outputs parameter
		if implicit_outputs ~= nil then
			local t = ninja.as_list(implicit_outputs)
			if #t > 0 then
				tinsert(out_outputs, '|')
				map(ninja.escape_path, t, out_outputs)
			end
		end

		-- Write build line
		self:_line(string.format('build %s: %s', join(out_outputs),
		                          join(all_inputs)))

		-- Handle build-specific variables
		if type(variables) == 'table' then
			local key, value
			if iskeyed(variables) then
				for key,value in pairs(variables) do
					self:variable(key, value, 1)
				end
			else
				for _,kvpair in pairs(variables) do
					key, value = unpack(kvpair)
					self:variable(key, value, 1)
				end
			end
		elseif variables ~= nil then
			error('Type error: if specified, variables should be a table!')
		end

		-- chain it
		return self
	end

	--- Include statement
	-- Used to include another .ninja file into the current scope.
	-- @string path .ninja file to include in the current scope
	-- @bool[opt=false] raw controls whether to escape path or leave it raw
	-- @treturn Writer returns self
	function Writer:include(path, raw)
		if not raw then path = ninja.escape_path(path) end
		return self:_line('include ' .. path)
	end

	--- Subninja statement
	-- Used to include another .ninja file, introducing a new scope.
	-- @string path .ninja file to use for the new scope
	-- @bool[opt=false] raw controls whether to escape path or leave it raw
	-- @treturn Writer returns self
	function Writer:subninja(path, raw)
		if not raw then path = ninja.escape_path(path) end
		return self:_line('subninja ' .. path)
	end

	--- Default target(s) statement.
	-- @tparam ?string|{string,...} targets default build target(s)
	-- @treturn Writer returns self
	function Writer:default(targets)
		return self:_line('default ' .. join(ninja.as_list(targets)))
	end

	--- Close the writer's output.
	function Writer:close()
		self.output:flush()
		self.output:close()
	end

	--- Writer Internals
	-- @section writer_private

	--- Refactored to a separate method in order to patch during tests.
	-- @param output The object we're testing 
	-- @treturn boolean
	function Writer:_isfile(output)
		return (type(output) == 'userdata' and io.type(output) == 'file') or
		       (type(output) == 'table' and isfileimpl(output))
	end

	--- Write 'text' to output with tracking for blank lines.
	-- Wasn't in the original ninja_syntax, but whatever.
	-- @string text output text
	-- @bool[opt=false] lineblank Whether or not text is a blank line.
	-- @treturn Writer returns self
	function Writer:_write(text, lineblank)
		self.output:write(text)
		self._P.lineblank = lineblank or false
		return self
	end

	--- Write 'text' word-wrapped at self.width characters.
	-- @string text Text to word-wrap
	-- @int[opt=0] indent Indent level
	-- @treturn Writer returns self
	function Writer:_line(text, indent)
		-- indent is at 0 by default
		indent = indent or 0

		-- avoid processing the same logic multiple times
		local leading = strrep('  ', indent)
		local targetlen = self.width - strlen(leading)

		while strlen(text) + strlen(leading) > self.width do
			-- The text is too wide; wrap if possible.

			-- Find the rightmost space that would obey our width constraint and
			-- that's not an escaped space.
			local available = targetlen - 2 -- strlen(' $')
			local space =  nextwrap(text, available)
			if space < 1 then
				-- didn't work - try to find the first non-escaped space then
				space = wrapafter(text, available)
			end
			
			if space < 1 then
				-- still no dice - give up on wrapping
				break
			end

			self:_write(leading .. substr(text, 1, space - 1) .. ' $'):newline()
			text = substr(text, space + 1)
			leading = strrep('  ', indent+2)
			targetlen = self.width - strlen(leading)
		end

		-- Finally, write to output - chain it
		return self:_write(leading .. text):newline()
	end

	--- Counts the '$' characters preceding str[index].
	-- @string str subject string
	-- @int index the target index
	-- @treturn int the count of '$' characters
	function Writer:_count_dollars_before_index(str, index)
		-- Exposing this solely to maintain an identical interface with
		-- ninja_syntax.py's Writer class.
		return count_dollars_before_index(str, index)
	end

	-- Export module members
	ninja.Writer = Writer
end

return ninja
