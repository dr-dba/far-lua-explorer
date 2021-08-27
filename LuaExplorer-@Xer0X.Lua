--[[
if true then return end --]]

--[[
Original version of @JD Lua Explorer "Advanced":
https://gist.github.com/johnd0e/5110ddfb3291928a7f484cd38f23ff87
https://forum.farmanager.com/viewtopic.php?t=7988
https://forum.farmanager.com/viewtopic.php?t=7521

Modified and even more "advanced" Lua Explorer @Xer0X:
https://github.com/dr-dba/far-lua-explorer/
https://forum.farmanager.com/viewtopic.php?f=15&t=12374

Mutual dependencies for "Lua Explorer @Xer0X":
https://github.com/dr-dba/far-lua-internals
https://github.com/dr-dba/far-lua-diagnostics
https://github.com/dr-dba/far-lua-general-utils
]]

local Info = Info or package.loaded.regscript or function(...) return ... end -- luacheck: ignore 113/Info
local nfo = Info { _filename or ...,
	name		= "Lua Explorer eXtended";
	description	= "Explore Lua environment in your Far manager (+@Xer0X mod.)";
	id		= "C61B1E8D-71D4-445C-85A6-35EA1D5B6EF3";
	version		= "2.4";
	version_mod	= "1.5.0";
	author		= "jd";
	author_mod	= "Xer0X";
	url		= "http://forum.farmanager.com/viewtopic.php?f=60&t=7988";
	url_mod		= "https://github.com/dr-dba/far-lua-explorer";
	licence		= [[
based on Lua Explorer by EGez:
http://forum.farmanager.com/viewtopic.php?f=15&t=7521

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
ANY USE IS AT YOUR OWN RISK.]];
	help = function(nfo) far.Message(nfo.helpstr, ('%s v%s'):format(nfo.name,nfo.version), nil, "l") end;
	options = {
		sort_tables_first = true,
		sort_ignore_case = true,
		sort_apply = true,
		chars = {
			['table'] = '≡',    -- ⁞≡•·÷»›►
			['function'] = '˜', -- ᶠ¨˝˜
		},
		bin_string = '#string',
	};
}
if not nfo or nfo.disabled then return end
local O = nfo.options
assert(far, 'This is LuaExplorer for Far manager')
local uuid	= win.Uuid('7646f761-8954-42ca-9cfc-e3f98a1c54d3')
nfo.helpstr	= [[

There are some keys available:

F1              Show this help
F4              Edit selected object
F9              Show registry
Del             Delete selected object
Ins             Add an object to current table
Ctrl+M          Show metatable
Ctrl+F          Show/hide functions
Ctrl+T          Toggle sort by type
Ctrl+I          Toggle ignore case

for functions:

Enter           Call function (params prompted)
F3              Show some function info
Shift+F3        Show some function info (LuaJiT required)
Alt+F4          Open function definition (if available) in editor at current line
Ctrl+Alt+F4     Open function definition (if available) in editor on declaration line start
Ctrl+Right      The function params
Ctrl+Up         Show upvalues (editable)
Ctrl+Down       Show environment (editable)

Copy to clipboard:

Ctrl+Ins        value
CtrlAlt+Insert  value without starting "_G.."
Ctrl+Shift+Ins  key
]]
if not Xer0X then Xer0X = { } end
local tbl_omit_type = { }
local brkeys = { }

-- format values for menu items and message boxes
local function fnc_val_fmt(val, mode)
	local	val_res
	local	val_type = type(val)
	if	val_type == 'string'
	then
		val_res = val
		if not	val_res:utf8valid()
		then
			local utf_8, err = win.Utf16ToUtf8(win.MultiByteToWideChar(val, win.GetACP()));
			val_res = utf_8 or err
			val_type = O.bin_string
		end
		if	val_res:match('%z')
		or	mode == 'edit'
		then    val_res = ('%q'):format(val_res)
		elseif	mode ~= 'view' and (
				mode ~= 'list' or
				val_res == '' or
				val_res:sub(-1, -1) == " "
					)
		then	val_res = '"'..val_res..'"'
		end
	elseif
		val_type == "number"
	then
		val_res = (mode == "edit" and "0x%x --[[ %s ]]" or "0x%08x (%s)"):format(val, val)
	elseif
		val_type == "table"
	then
		local disp = rawget(val, "_LEX_DISPLAY_STR")
		val_res = disp and (type(disp) == "function" and disp(val) or tostring(disp)) 
			or tostring(val)
	else
		val_res = tostring(val)
	end
	return	val_res, val_type
end

-- make menu item for far.Menu(...)
local KEY_WIDTH = 30
local ITEM_FMT = ('%%-%s.%ss'):format(KEY_WIDTH, KEY_WIDTH)..'%s%-8s │%-25s'

local function fnc_menu_item_make(val_key, sval, val_type)
	local key_fmt = fnc_val_fmt(val_key, 'list')
	local border = key_fmt:len() <= KEY_WIDTH and '│' or '…'
	return {
		text	= ITEM_FMT:format(key_fmt, border, val_type, sval),
		key	= val_key,
		type	= val_type,
		checked	= O.chars[val_type]
	}
end

local function fnc_is_LE_obj(obj)
	return 2 < ( 0
		+ ("nil" ~= type(obj.obj)	and 1 or 0)
		+ ("nil" ~= type(obj.menu_idx ) and 1 or 0)
		+ ("nil" ~= type(obj.menu_item) and 1 or 0)
		+ ("nil" ~= type(obj.menu_item) and 1 or 0)
		+ ("nil" ~= type(obj.child_menu_item_txt) and 1 or 0)
		+ ("nil" ~= type(obj.child_menu_item_idx) and 1 or 0)
			)
end

local fnc_tbl_sort__simple = function(v1, v2)
	return v1.text < v2.text
end

local fnc_tbl_sort__case = function(v1, v2)
	if O.sort_ignore_case
	then return v1.text:lower() < v2.text:lower()
	else return v1.text < v2.text
	end
end

local fnc_tbl_sort__tables_first = function(v1, v2)
	if	(v1.type == 'table')
	~=	(v2.type == 'table')
	then	return v1.type == 'table'
	else    return v1.text < v2.text
	end
end

local LEX_DATA_HIDE = true
local function fnc_default_hidden_meta_props_set(tbl_hide_vals)
	if not LEX_DATA_HIDE then return tbl_hide_vals end
	if not	tbl_hide_vals
	then	tbl_hide_vals = { }
	end
       	tbl_hide_vals["_LEX_VAR_MAP"]	=	true
       	tbl_hide_vals["_LEX_VARARG_VALS"] =	true
	tbl_hide_vals["_LEX_FNC_KEY_WEIGHT"] =	true
	tbl_hide_vals["_LEX_LEV_STK_FUNC"] = 	true
	tbl_hide_vals["_LEX_LEV_STK_WHAT"] = 	true
	tbl_hide_vals["_LEX_DISPLAY_NAME"] =	true
	tbl_hide_vals["_LEX_DISPNAME_SEP"] =	true
	tbl_hide_vals["_LEX_HIDDEN_PROPS"] =	true
	tbl_hide_vals["_LEX_DISPLAY_STR"] =	true
	return tbl_hide_vals
end

local fnc_menu_item_cust_sort = function(tbl_object, fnc_menu_item_key_weight, fnc_fallback_sort)
	if fnc_menu_item_key_weight
	then return function(v1, v2)
			local	v1_weight = fnc_menu_item_key_weight(v1.key)
			local	v2_weight = fnc_menu_item_key_weight(v2.key)
			if	v1_weight
			or	v2_weight
			then	return  (v1_weight or 1000) <
					(v2_weight or 1000)
			else	fnc_fallback_sort(v1, v2)
			end
		end
	else return fnc_fallback_sort
	end
end

local fnc_tbl_sort__tables_first__case_insens = function(v1, v2)
	if not	O.sort_tables_first
	then	return fnc_tbl_sort__case(v1, v2)
	elseif	v1.type == v2.type
	then	return fnc_tbl_sort__case(v1, v2)
	elseif	v1.type == "table"
	then	return true
	elseif 	v2.type == "table"
	then 	return false
	else	return fnc_tbl_sort__case(v1, v2)
	end
end

local function fnc_menu_items_add(tbl_menu_source, tbl_menu_src_idx, tbl_hide_vals, tbl_menu_items, tbl_item_props)
	for key in pairs(tbl_menu_src_idx or tbl_menu_source)
	do	if not tbl_hide_vals[key]
		then	local sval, vt = fnc_val_fmt(tbl_menu_source[key], 'list')
			if not tbl_omit_type[vt]
			then tbl_menu_items[#tbl_menu_items + 1] = fnc_menu_item_make(key, sval, vt)
			end
			tbl_item_props[key] = tbl_menu_source[key]
		end
	end
	return tbl_menu_items, tbl_item_props
end -- fnc_menu_items_add

local function fnc_hidden_props_detect(tbl_menu_source)
	if type(tbl_menu_source) ~= "table" then return end
	local	has_hidden_props
	--[[ Far uses some properties that in fact are functions in tbl_menu_source.properties
	but they logically belong to the object itself. It's all Lua magic ;) ]]
--	if getmetatable(tbl_menu_source) == "access denied" then ...
--	if type(tbl_menu_source.properties) == 'table' and not rawget(tbl_menu_source, 'properties') then ..
	local	props_ok, props = pcall(function() return tbl_menu_source.properties end)
--	if not	props_ok then far.Message(props, 'Error in __index metamethod', nil, 'wl') end
	if	type(props) == 'table'
	and not rawget(tbl_menu_source, 'properties')
	then	has_hidden_props = true
	end
	return	has_hidden_props
end -- fnc_hidden_props_detect

-- create sorted menu items with associated keys
local function makeMenuItems(tbl_menu_source, obj_nav, tbl_hide_vals)
	local tbl_menu_items = { }
	local tbl_item_props = { }
	do	-- grab all 'real' keys
		fnc_menu_items_add(tbl_menu_source, nil,			tbl_hide_vals, tbl_menu_items, tbl_item_props)
	end
	local	has_hidden_props = fnc_hidden_props_detect(tbl_menu_source)
	if	has_hidden_props
	then	fnc_menu_items_add(tbl_menu_source, tbl_menu_source.properties, tbl_hide_vals, tbl_menu_items, tbl_item_props)
	end
	if	O.sort_apply
	then	local fnc_sort = fnc_menu_item_cust_sort(tbl_menu_source, rawget(tbl_menu_source, "_LEX_FNC_KEY_WEIGHT"), fnc_tbl_sort__tables_first__case_insens)
		table.sort(tbl_menu_items, fnc_sort)
	end
	local	obj_nav_idx, obj_nav_val
	if	obj_nav
	then	obj_nav_val = fnc_is_LE_obj(obj_nav) and obj_nav.obj_val or obj_nav
		for key, val in pairs(tbl_menu_items)
		do	if	val.key == obj_nav_val
			then	obj_nav_idx = key
				break
			end
		end
	end
	return tbl_menu_items, tbl_item_props, obj_nav_idx, has_hidden_props
end -- makeMenuItems

local function getres(stat, ...) return stat, stat and { ... } or (...) and tostring(...) or '', select('#', ...) end

local function checknil(t, n) for ii = 1, n do if t[ii] == nil then return true end end end

-- custom concat (applies 'tostring' to each item)
local function concat(tbl_inp, delim, pos1, pos2)
--	assert(delim and pos1 and pos2)
	local str = pos2 > 0 and tostring(tbl_inp[pos1]) or ''
	for ii = pos1 + 1, pos2 do str = str..delim..tostring(tbl_inp[ii]) end
	return str
end

local function luaexp_prompt(Title, Prompt, Src, nArgs)
	repeat
		local	expr = far.InputBox(nil, Title:gsub('&', '&&', 1), Prompt, Title, Src, nil, nil, far.Flags.FIB_ENABLEEMPTY)
		if not	expr then break end
		local	f, err = loadstring('return '..expr)
		if	f
		then	local	stat, res, n = getres(pcall(f))
			if	stat
			then
				if not nArgs or (nArgs == n and not checknil(res, n))
				then	return res, n, expr
				else	err = ([[
%d argument(s) required

  Expression entered: %q
  Evaluated as %d arg(s): %s]]):format(nArgs, expr, n, concat(res, ',', 1, n))
				end
			else
				err = res
			end
		end
		far.Message(err, 'Error', nil, 'wl')
	until false
end

-- edit or remove object at obj[key]
local function editValue(obj, key, title, del)
	if	del
	then
		local message = ('%s is a %s, do you want to remove it?')
			:format(fnc_val_fmt(key), type(obj[key]):upper())
		if 1 == far.Message(message, 'REMOVE: '..title, ';YesNo', 'w')
		then	obj[key] = nil
		end
	else
		local v, t = fnc_val_fmt(obj[key], 'edit')
		if t == 'table' or t == 'function' then	v = ''	end
		local	prompt = ('%s is a %s, type new value as Lua code'):format(fnc_val_fmt(key), t:upper())
		local	res = luaexp_prompt('EDIT: '..title, prompt, v, 1)
		if	res
		then	if t == O.bin_string
			then res[1] = win.WideCharToMultiByte(win.Utf8ToUtf16(res[1]), win.GetACP())
			end
			obj[key] = res[1]
		end
	end
end

-- add new element to obj
local function insertValue(obj, title)
	local	res = luaexp_prompt('INSERT: '..title, 'type the key and value comma separated as Lua code', nil, 2)
	if	res then obj[res[1]] = res[2] end
end

local function getfParamsNames(f)
	-- check _VERSION > "Lua 5.1"
	if not jit then	return '...' end
	local info = debug.getinfo(f)
	local params = { }
	for ii = 1, info.nparams or 1000
	do params[ii] = debug.getlocal(f, ii) or ("<%i>"):format(ii) -- C?
	end
	if info.isvararg then params[#params + 1] = '...' end
	local param_str = #params > 0 and table.concat(params, ', ') or '<none>'
	return param_str, params
end

if not	_G.Xer0X
then	_G.Xer0X = { }
end
if not	_G.Xer0X.tbl_explorer_reopen_chain
then	_G.Xer0X.tbl_explorer_reopen_chain = { }
end
local tbl_reopen_paths = Xer0X.tbl_explorer_reopen_chain

-- show a menu whose items are associated with the members of given object
local function process(obj, path_title, action, obj_root, tbl_open_path, tbl_hide_vals)
	local	obj_type = type(obj)
	if	obj_type == "nil"
	then	far.Message("Not provided an object to explore", "LuaExplorer eXtended", nil, 'wl')
		return
	end
	if not	tbl_hide_vals
	then	tbl_hide_vals = fnc_default_hidden_meta_props_set()
	end
	local	tbl_ReOp_path, is_obj_root
	if	obj_root
	then	tbl_ReOp_path = tbl_reopen_paths[obj_root]
	else	tbl_ReOp_path = tbl_reopen_paths[obj]
		is_obj_root = true
		obj_root = obj
		if not	tbl_open_path
		then	tbl_open_path = { }
		end
		if not	tbl_ReOp_path
		then	tbl_ReOp_path = { }
			tbl_reopen_paths[obj] = tbl_ReOp_path
		elseif	#tbl_open_path > 0
		then	for ii = 1, #tbl_open_path, -1
			do	local obj_path_item = table.remove(tbl_ReOp_path, 1)
				if type(obj_path_item) == nil then break end
				if not	fnc_is_LE_obj(tbl_open_path[ii])
				and	obj_path_item.menu_item.key == tbl_open_path[ii]
				then	local obj_new = { }
					for ii_obj_key, ii_obj_val in pairs(obj_path_item)
					do obj_new[ii_obj_key] = ii_obj_val
					end
					tbl_open_path[ii] = obj_new
				end
			end
			while #tbl_ReOp_path > 0 do tbl_ReOp_path[#tbl_ReOp_path] = nil end
		else	while #tbl_ReOp_path > 0
			do table.insert(tbl_open_path, table.remove(tbl_ReOp_path, 1))
			end
		end
	end
	local tbl_cur_obj = is_obj_root and tbl_ReOp_path or tbl_ReOp_path[#tbl_ReOp_path]
	if type(path_title) ~= "string"
	then	path_title = ""
	end
	-- here you can insert your custom actions
	if	action
	and	brkeys[action]
	then	brkeys[action]({ obj }, 1, path_title);
		return
	end
	local mprops = {
		Id = uuid,
		Bottom = 'F1, F3, F4, Del, Ctrl+M',
		Flags = {
			FMENU_SHOWAMPERSAND =	1,
			FMENU_WRAPMODE =	1
		}
	}
	local menu_item, menu_idx, obj_ret, obj_rem, obj_nav
	--[[ some member types, need specific behavior:
		* tables are submenus
		* functions can be called ]]
	if	obj_type == 'function'
	then
		local args, n, expr = luaexp_prompt(
			'CALL:'..path_title,
			('arguments: %s (type as Lua code or leave empty)')
				:format(getfParamsNames(obj))
					)
		if not args then return end
		-- overwrite the function object with its return values
		local	stat, res = getres(pcall(obj, unpack(args, 1, n)))
		if not	stat
		then	far.Message(
				('%s\n  CALL: %s (%s)\n  argument(s): %d'..(n > 0 and ', evaluated as: %s' or ''))
					:format(res, path_title, expr, n, concat(args, ',', 1, n)),
				'Error', nil, 'wl'
			)
			return
		end
		obj = res
		path_title = ('%s(%s)'):format(path_title, expr)
	-- other values are simply displayed in a message box
	elseif	obj_type ~= 'table'
	then	local value = fnc_val_fmt(obj, 'view')
		far.Message(value, path_title:gsub('&', '&&', 1), nil, value:match('\n') and 'l' or '')
		return
	end
	-- show this menu level again after each return from a submenu/function call ...
	local obj_title_separ = rawget(obj, "_LEX_DISPNAME_SEP") or "."
	repeat
		local menu_items, item_props, obj_nav_idx, obj_props_hidden = makeMenuItems(obj, --[[! can be NIL:]] tbl_open_path[1], tbl_hide_vals)
		mprops.Title = path_title..' ('..#menu_items..')'..(tbl_omit_type['function'] and '*' or '')
		mprops.SelectIndex = obj_nav_idx or tbl_cur_obj.child_menu_item_idx
		tbl_cur_obj.obj_props = item_props
		if	tbl_open_path
		and 	#tbl_open_path > 0
		then	menu_item= tbl_open_path[1].menu_item or obj_nav_idx and menu_items[obj_nav_idx]
			menu_idx = tbl_open_path[1].menu_idx  or obj_nav_idx
			obj_nav = table.remove(tbl_open_path, 1)
			if not	menu_item
			then	--[[ the object changed!
				it means that the old name dissapeared ]]
				far.Message(string.format("The key [%s] was removed", obj_nav), path_title, nil, "wl")
				obj_ret = "back"
			end
		else
		--	mprops.SelectIndex = mprops.SelectIndex or tbl_cur_obj.child_menu_item_idx
			menu_item, menu_idx = far.Menu(mprops, menu_items, brkeys)
		end
		if	menu_idx
		then	mprops.SelectIndex = menu_idx
			tbl_cur_obj.child_menu_item_idx = menu_idx
			tbl_cur_obj.child_menu_item_txt = menu_item.text
		end
		-- show submenu/call function ...
		if	menu_item
		then
			if	menu_item.name == "goBack"
			then
				obj_ret = "back"
			else
				local	obj_key_child = menu_item.key or menu_idx > 0 and menu_items[menu_idx].key
				local	obj_child = obj[obj_key_child]
				local	title_child = type(obj_child) == "table"
						and not rawget(obj_child, "_LEX_HIDDEN_PROPS")
						and	rawget(obj_child, "_LEX_DISPLAY_NAME")
					or tostring(obj_key_child)
				if type(title_child) == "boolean"
				then
				end
				if	title_child == "" then title_child = "<EMPTY-STR>" end
				local path_title_child = (path_title ~= '' and path_title..obj_title_separ or "")..title_child
				if	menu_item.key ~= nil
				then	if type(obj_child) ~= "nil"
					then	table.insert(tbl_ReOp_path, {
							obj_val  = obj_child,
							obj_key  = obj_key_child,
							menu_idx = menu_idx,
							menu_item= menu_item,
							child_menu_item_txt = obj_nav and obj_nav.child_menu_item_txt,
							child_menu_item_idx = obj_nav and obj_nav.child_menu_item_idx,
						})
						obj_ret = process(obj_child, path_title_child, nil, obj_root, tbl_open_path, tbl_hide_vals)
						if	obj_ret ~= "exit"
						then	obj_rem = table.remove(tbl_ReOp_path)
						end
					end
				elseif	menu_item.action
				then	if "break" == menu_item.action(
						obj, obj_key_child, path_title_child, item_props, obj_props_hidden, tbl_hide_vals, tbl_ReOp_path
							)
					then return
					end
				end
			end
		end
		if not	menu_item
		and not obj_ret
		then	obj_ret = "exit"
		end
	-- until the user is bored and goes back ;)
	until	obj_ret == "exit"
	or	obj_ret == "back"
	if	obj_ret == "back"
	then	--[[ no back-propagation allowed!
		so that the one back will do only one backstep:]]
		obj_ret = nil
	end
	return	obj_ret 
end

local function fnc_upvals_collect(fnc_inp, num_vals)
	local	tbl_upvals = { }
	local	ii_key, ii_val
	-- n: debug.getinfo(f).nups
	for	ii = 1, num_vals or 1000
	do	ii_key, ii_val = debug.getupvalue(fnc_inp, ii)
		if not ii_key then num_vals = ii - 1; break end
		tbl_upvals[ii_key] = ii_val
	end
	return tbl_upvals, num_vals
end

local function syncUpvalues(f, t, n)
	-- n: debug.getinfo(f).nups
	for i = (n or -1), (n and 1 or -1000), -1
	do
		local	k, v = debug.getupvalue(f, i)
		if not	k then break end
		if	t[k] ~= v
		then	assert(k == debug.setupvalue (f, i, t[k]))
		end
	end
end

local function fnc_func_info(obj, key, tbl_curr_path)
-- ###
if fnc_hidden_props_detect(obj) then return obj end
local	fnc_test = obj[key]
if	obj._LEX_LEV_STK_FUNC
then	obj = obj[string.format("INFUNC:%s/%s", obj._LEX_LEV_STK_WHAT, obj._LEX_LEV_STK_FUNC)]
	fnc_test = obj.func
end
local is_func = type(fnc_test) == 'function'
local is_info =
	not props_hidden
	and obj.linedefined
	and obj.source
	and obj.func
if not (is_func
or 	is_info)
then	for	ii_lev = #tbl_curr_path, 1, -1
	do	local	tbl_stk_inf = tbl_curr_path[ii_lev]
		local	obj_val = tbl_stk_inf.obj_val
		if	obj_val
		then
			local	what_fnc = obj_val._LEX_LEV_STK_WHAT
			local	name_fnc = obj_val._LEX_LEV_STK_FUNC
			if	name_fnc
			then	local	obj_props = tbl_stk_inf.obj_props
				repeat
					local	obj_inf_fnc = obj_props[string.format("INFUNC:%s/%s", what_fnc, name_fnc)]
					if	obj_inf_fnc.linedefined
					then	obj = obj_inf_fnc
						is_info = true
						break
					else	local is_caller_found
						for ii_key, ii_val in pairs(obj_props)
						do	if string.match(ii_key, "CALLER:")
							then	obj_props= obj_props[ii_key]
								name_fnc = obj_props._LEX_LEV_STK_FUNC
								what_fnc = obj_props._LEX_LEV_STK_WHAT
								is_caller_found = true
								break
							end
						end
						if not is_caller_found then break end
					end
				until false
				if is_info then break end
			end
		end
	end
end
local fnc_targ =
	is_func and fnc_test or
	is_info and obj.func
local dbg_info =
	is_info and obj or
	is_func and debug.getinfo(fnc_test, 'Slun')
return obj, is_func or is_info, fnc_targ, dbg_info
-- @@@
end -- fnc_func_info

brkeys = {
	{ BreakKey = 'F9', name = 'registry',
		action = function(info) process(debug.getregistry(), 'debug.getregistry:') end; },
	{ BreakKey = 'Ctrl+Insert',
		action = function(obj, key)
			-- todo: escape slashes etc
			local copy_val, copy_type = fnc_val_fmt(obj[key])
			far.CopyToClipboard(copy_val)
		end},
	{ BreakKey = 'CtrlShift+Insert',
		action = function(obj, key)
			local copy_val, copy_type = fnc_val_fmt(key, 'list')
			far.CopyToClipboard(copy_val)
		end},
	{ BreakKey = 'CtrlAlt+Insert',
		action = function(obj, key, kpath)
			local copy_val, copy_type = fnc_val_fmt(key, 'list')
			far.CopyToClipboard(kpath:gsub('^_G%.', '')..copy_val)
		end},
	{ BreakKey = 'Ctrl+Up',	name = 'upvalues',
		action = function(obj, key, kpath, props, props_hidden, tbl_vals_hidden, tbl_curr_path)
-- ###
local tbl_obj, is_func, fnc_targ, dbg_info = fnc_func_info(obj, key, tbl_curr_path)
if	is_func
then	if	dbg_info.what ~= 'C'
	or	true -- todo
	then	local	tbl_upvals, num_vals = fnc_upvals_collect(fnc_targ)
		if	num_vals > 0
		then	process(tbl_upvals, 'upvalues: '..kpath)
			syncUpvalues(fnc_targ, tbl_upvals, num_vals)
		else	far.Message(
				"No upvalues",
				dbg_info.name
					or key ~= "func" and key
					or string.gsub(string.gsub(kpath, "debug.getinfo: ", ""), ".func$", ""),
				nil,
				"w"
			)
		end
	end
end
-- @@@
		end; },
	{ BreakKey = 'Ctrl+Down', name = 'env',
		action = function(obj, key, kpath)
-- ###
local	f = obj[key];
local	t = type(f)
if	t == 'function'
or	t == 'userdata'
or	t == 'thread'
then
	local env = debug.getfenv(f)
	local env_is_glob = env == _G
        process(env, 'getfenv: '..kpath..(env_is_glob and " (_G)" or ""))
	--[[
	local dlg_res = far.Message('Show global environment?', '_G', ';OkCancel')
	if (env ~= _G or dlg_res == 1) and env and next(env)
	then process(env, 'getfenv: '..kpath)
	end --]]
end
-- @@@
		end; },
	{ BreakKey = 'Ctrl+Right', name = 'params',
		action = function(obj, key, kpath, props, props_hidden, tbl_vals_hidden, tbl_curr_path)
-- ###
local tbl_obj, is_func, fnc_targ, dbg_info = fnc_func_info(obj, key, tbl_curr_path)
if	is_func
then
	local	arg_str, obj_args = getfParamsNames(fnc_targ)
	if	arg_str:len() > 0
	then	process(obj_args, 'params (f): '..kpath)
	--[[	local name = debug.getinfo(f).name
		far.Message(('%s (%s)'):format(name or kpath, arg_str), 'params') --]]
	end
end
-- @@@
		end; },
	{ BreakKey = 'Alt+F4', name = 'edit',
		action = function(obj, key, kpath, props, props_hidden, tbl_vals_hidden, tbl_curr_path)
-- ###
local tbl_obj, is_func, fnc_targ, dbg_info = fnc_func_info(obj, key, tbl_curr_path)
if 	is_func
then
	local filename =
		dbg_info.source:match("^@(.+)$")
	local fileline =
		dbg_info.currentline	and
		dbg_info.currentline>=0 and
		dbg_info.currentline
			or
		dbg_info.linedefined	and
		dbg_info.linedefined>=0 and
		dbg_info.linedefined
	if filename
	then editor.Editor(filename, nil, nil, nil, nil, nil, nil, fileline)
	end
end
-- @@@
		end; },
	{ BreakKey = 'F3', name = 'info',
		action = function(obj, key, kpath, item_props, obj_props_hidden, tbl_hide_vals)
-- ###
local	func = obj[key]
local	ftype = type(func)
if	ftype == 'function'
then	local	dbg_info = debug.getinfo(func)
	if	dbg_info.namewhat == ""
	then	dbg_info.namewhat = nil
	end
	if	dbg_info.linedefined == -1
	then	dbg_info.linedefined = nil
	end
	if	dbg_info.currentline == -1
	then	dbg_info.currentline = nil
	end
	if	dbg_info.lastlinedefined == -1
	then	dbg_info.lastlinedefined = nil
	end
	dbg_info._LEX_FNC_KEY_WEIGHT = Xer0X.fnc_menu_dbg_inf_key_weight
	process(dbg_info, 'debug.getinfo: '..kpath, nil, nil, nil, tbl_hide_vals)
elseif	ftype == 'thread'
then	far.Message(debug.traceback(func, "level 0", 0):gsub('\n\t','\n   '), 'debug.traceback: '..kpath, nil, "l")
end
-- @@@
		end; },
	{ BreakKey = 'F4',
		action = function(obj, key, kpath) return key ~= nil and editValue(obj, key, kpath) end },
	{ BreakKey = 'Ctrl+F',
		action = function() tbl_omit_type['function'] = not tbl_omit_type['function'] end },
	{ BreakKey = 'Ctrl+T',
		action = function() O.sort_tables_first	= not O.sort_tables_first	end },
	{ BreakKey = 'Ctrl+I',
		action = function() O.sort_ignore_case	= not O.sort_ignore_case	end },
	{ BreakKey = 'Ctrl+S',
		action = function() O.sort_apply	= not O.sort_apply		end },
	{ BreakKey = 'Ctrl+M', name = 'mt',
		action = function(obj, key, kpath)
-- ###
local mt = key ~= nil and debug.getmetatable(obj[key])
return mt and process(mt, 'METATABLE: '..kpath)
-- @@@
		end; },
	{ BreakKey = 'DELETE',	action = function(obj, key, kpath) return key ~= nil and editValue(obj, key, kpath, true) end },
	{ BreakKey = 'INSERT',	action = function(obj, key, kpath) insertValue(obj, kpath:sub(1, -(#tostring(key) + 2))) end },
	{ BreakKey = 'F1',	action = function() nfo:help() end},
	{ BreakKey = nil,	name = 'addBrKeys',
		action = function(obj, key)
-- ###
local	addbrkeys = obj[key]
for	ii = 1, #addbrkeys
do	local bk = addbrkeys[ii]
	local BreakKey = bk.BreakKey
	local pos
	for jj = 1, #brkeys
	do	if brkeys[jj].BreakKey == BreakKey
		then	pos = jj
			break
		end
	end
	if	pos
	then	brkeys[pos] = bk
	else	table.insert(brkeys, bk)
		if bk.name
		then brkeys[bk.name] = bk.action
		end
	end
end
return "break"
-- @@@
		end; },
	{ BreakKey = 'BS', name = "goBack", action = function() return "goBack" end }
}

--[[ if LuaJiT is used,
maybe we can show some more function info]]
if	jit
then
	local fnc_jit_inf = require('jit.util').funcinfo
	table.insert(
		brkeys,
		{
			name = 'jitinfo',
			BreakKey = 'Shift+F3',
			action = function(obj, key, kpath, props, props_hidden, tbl_vals_hidden, tbl_curr_path)
				local tbl_obj, is_func, fnc_targ, dbg_info = fnc_func_info(obj, key, tbl_curr_path)
				if      is_func
				then
				--[[	local name_x = debug.getinfo(obj[key], "n").name
					far.Message(name_x) --]]
					process(fnc_jit_inf(fnc_targ), 'jit.util.funcinfo: '..kpath)
				end
			end,
		}
	)
end

for ii = 1, #brkeys
do	local bk = brkeys[ii]
	if bk.name then	brkeys[bk.name] = bk.action end
end

nfo.execute = function()
	process(_G, '')
--	require("le")(_G, '_G')
end

if
	Macro
then
-- ###
Macro { description = "Lua Explorer eXtended";
	area = "Common";
	key = "RCtrlShiftF12";
	action = nfo.execute
}
-- @@@
elseif
	_filename
then
--	process(_G, '')
	_G.le = process
	_G.LE = process
else
	return	process, fnc_default_hidden_meta_props_set
-- if ... == "le" then
end

--[[ it's possible to call via lua:, e.g. from user menu:
lua:dofile(win.GetEnv("FARPROFILE")..[[\Macros\scripts\le.lua] ])(_G,'_G')
lua:require("le")(_G,'_G')
--]]

-- @@@@@
