
local gravity = tonumber(core.settings:get("movement_gravity")) or 9.81
local node_fall_hurt = core.settings:get_bool("node_fall_hurt") ~= false
local math_pi = math.pi
local get_id = core.get_node_raw
local get_id_name = core.get_name_from_content_id
local get_node = core.get_node

if get_id then get_node = function(pos)

		local id, p1, p2, pos_ok = get_id(pos.x, pos.y, pos.z)

		return {name = get_id_name(id), param1 = p1, param2 = p2, loaded = pos_ok}
	end
end

-- Add damage group to node function

local function add_fall_damage(node, damage)

	if core.registered_nodes[node] then

		local group = core.registered_nodes[node].groups

		group.falling_node_damage = damage

		core.override_item(node, {groups = group})
	else
		print (node .. " not found to add falling_node_damage to")
	end
end

-- Override certain falling nodes to add damage

core.after(0, function()

	add_fall_damage("default:sand", 2)
	add_fall_damage("default:desert_sand", 2)
	add_fall_damage("default:silver_sand", 2)
	add_fall_damage("default:gravel", 3)
	add_fall_damage("caverealms:coal_dust", 2)
	add_fall_damage("tnt:tnt_burning", 4)
	add_fall_damage("anvils:anvil", 5)
end)

-- Damage function

local function fall_hurt_check(self, obj)

	-- Get damage level from falling_node_damage group
	local damage = core.registered_nodes[self.node.name] and
			core.registered_nodes[self.node.name].groups.falling_node_damage

	if not node_fall_hurt or not damage then return end

	local name = obj and obj:get_luaentity() and obj:get_luaentity().name
			or obj:is_player() and "player"

	if name and name ~= "__builtin:item" and name ~= "__builtin:falling_node" then
		obj:punch(self.object, 4.0, {damage_groups = {fleshy = damage}}, nil)
	end
end


local facedir_to_euler = {
	{y = 0, x = 0, z = 0},
	{y = -math_pi/2, x = 0, z = 0},
	{y = math_pi, x = 0, z = 0},
	{y = math_pi/2, x = 0, z = 0},
	{y = math_pi/2, x = -math_pi/2, z = math_pi/2},
	{y = math_pi/2, x = math_pi, z = math_pi/2},
	{y = math_pi/2, x = math_pi/2, z = math_pi/2},
	{y = math_pi/2, x = 0, z = math_pi/2},
	{y = -math_pi/2, x = math_pi/2, z = math_pi/2},
	{y = -math_pi/2, x = 0, z = math_pi/2},
	{y = -math_pi/2, x = -math_pi/2, z = math_pi/2},
	{y = -math_pi/2, x = math_pi, z = math_pi/2},
	{y = 0, x = 0, z = math_pi/2},
	{y = 0, x = -math_pi/2, z = math_pi/2},
	{y = 0, x = math_pi, z = math_pi/2},
	{y = 0, x = math_pi/2, z = math_pi/2},
	{y = math_pi, x = math_pi, z = math_pi/2},
	{y = math_pi, x = math_pi/2, z = math_pi/2},
	{y = math_pi, x = 0, z = math_pi/2},
	{y = math_pi, x = -math_pi/2, z = math_pi/2},
	{y = math_pi, x = math_pi, z = 0},
	{y = -math_pi/2, x = math_pi, z = 0},
	{y = 0, x = math_pi, z = 0},
	{y = math_pi/2, x = math_pi, z = 0}
}

--
-- Falling stuff
--

core.register_entity(":__builtin:falling_node", {
	initial_properties = {
		visual = "node",
		physical = true,
		is_visible = false,
		collide_with_objects = true,
		collisionbox = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
	},

	node = {},
	meta = {},
	floats = false,

	set_node = function(self, node, meta)
		node.param2 = node.param2 or 0
		self.node = node
		meta = meta or {}
		if type(meta.to_table) == "function" then
			meta = meta:to_table()
		end
		for _, list in pairs(meta.inventory or {}) do
			for i, stack in pairs(list) do
				if type(stack) == "userdata" then
					list[i] = stack:to_string()
				end
			end
		end
		local def = core.registered_nodes[node.name]
		if not def then
			-- Don't allow unknown nodes to fall
			core.log("info",
				"Unknown falling node removed at "..
				core.pos_to_string(self.object:get_pos()))
			self.object:remove()
			return
		end
		self.meta = meta

		-- Cache whether we're supposed to float on water
		self.floats = core.get_item_group(node.name, "float") ~= 0

		-- Save liquidtype for falling water
		self.liquidtype = def.liquidtype

		-- Set up entity visuals
		-- For compatibility with older clients we continue to use "item" visual
		-- for simple situations.
		local drawtypes = {normal=true, glasslike=true, allfaces=true, nodebox=true}
		local p2types = {none=true, facedir=true, ["4dir"]=true}
		if drawtypes[def.drawtype] and p2types[def.paramtype2]
				and def.use_texture_alpha ~= "blend" then
			-- Calculate size of falling node
			local s = vector.zero()
			s.x = (def.visual_scale or 1) * 0.667
			s.y = s.x
			s.z = s.x
			-- Compensate for wield_scale
			if def.wield_scale then
				s.x = s.x / def.wield_scale.x
				s.y = s.y / def.wield_scale.y
				s.z = s.z / def.wield_scale.z
			end
			self.object:set_properties({
				is_visible = true,
				visual = "item",
				wield_item = node.name,
				visual_size = s,
				glow = def.light_source,
			})
			-- Rotate as needed
			if def.paramtype2 == "facedir" then
				local fdir = node.param2 % 32 % 24
				local euler = facedir_to_euler[fdir + 1]
				if euler then
					self.object:set_rotation(euler)
				end
			elseif def.paramtype2 == "4dir" then
				local fdir = node.param2 % 4
				local euler = facedir_to_euler[fdir + 1]
				if euler then
					self.object:set_rotation(euler)
				end
			end
		elseif def.drawtype ~= "airlike" then
			self.object:set_properties({
				is_visible = true,
				node = node,
				glow = def.light_source,
			})
		end

		-- Set collision box (certain nodeboxes only for now)
		local nb_types = {fixed = true, leveled = true, connected = true}
		if def.drawtype == "nodebox" and def.node_box and
			nb_types[def.node_box.type] and def.node_box.fixed then
			local box = table.copy(def.node_box.fixed)
			if type(box[1]) == "table" then
				box = #box == 1 and box[1] or nil -- We can only use a single box
			end
			if box then
				if def.paramtype2 == "leveled" and (self.node.level or 0) > 0 then
					box[5] = -0.5 + self.node.level / 64
				end
				self.object:set_properties({collisionbox = box})
			end
		end
	end,

	get_staticdata = function(self)
		return core.serialize({node = self.node, meta = self.meta})
	end,

	on_activate = function(self, staticdata)
		self.object:set_armor_groups({immortal = 1})
		self.object:set_acceleration(vector.new(0, -gravity, 0))

		local ds = core.deserialize(staticdata)
		if ds and ds.node then
			self:set_node(ds.node, ds.meta)
		elseif ds then
			self:set_node(ds)
		elseif staticdata ~= "" then
			self:set_node({name = staticdata})
		end
	end,

	try_place = function(self, bcp, bcn)
		local bcd = core.registered_nodes[bcn.name]
		-- Add levels if dropped on same leveled node
		if bcd and bcd.paramtype2 == "leveled" and
				bcn.name == self.node.name then
			local addlevel = self.node.level
			if (addlevel or 0) <= 0 then
				addlevel = bcd.leveled
			end
			if core.add_node_level(bcp, addlevel) < addlevel then
				return true
			elseif bcd.buildable_to then
				-- Node level has already reached max, don't place anything
				return true
			end
		end

		-- Decide if we're replacing the node or placing on top
		-- This condition is very similar to the check in core.check_single_for_falling(p)
		local np = vector.copy(bcp)
		if bcd and bcd.buildable_to
				and -- Take "float" group into consideration:
				(
					-- Fall through non-liquids
					not self.floats or bcd.liquidtype == "none" or
					-- Only let sources fall through flowing liquids
					(self.floats and self.liquidtype ~= "none" and bcd.liquidtype ~= "source")
				) then
			core.remove_node(bcp)
		else
			-- We are placing on top so check what's there
			np.y = np.y + 1

			local n2 = get_node(np)
			local nd = core.registered_nodes[n2.name]
			if not nd or nd.buildable_to then
				core.remove_node(np)
			else
				-- 'walkable' is used to mean "falling nodes can't replace this"
				-- here. Normally we would collide with the walkable node itself
				-- and place our node on top (so `n2.name == "air"`), but we
				-- re-check this in case we ended up inside a node.
				if not nd.diggable or nd.walkable then
					return false
				end
				nd.on_dig(np, n2, nil)
				-- If it's still there, it might be protected
				if get_node(np).name == n2.name then
					return false
				end
			end
		end

		-- Create node
		local def = core.registered_nodes[self.node.name]
		if def then
			core.add_node(np, self.node)
			if self.meta then
				core.get_meta(np):from_table(self.meta)
			end
			local snd, gain = "default_place_node", 1.0
			if bcd.groups.water then
				snd = "default_water_footstep" ; gain = 0.4
			elseif bcd.groups.lava then
				snd = "default_cool_lava" ; gain = 0.1
			elseif def.sounds and def.sounds.place then
				snd = def.sounds.place
			end
			core.sound_play(snd, {pos = np, max_hear_distance = 20, gain = gain}, true)
		end
		core.check_for_falling(np)
		return true
	end,

	on_step = function(self, dtime, moveresult)

		local pos = self.object:get_pos()

		-- Fallback code since collision detection can't tell us
		-- about liquids (which do not collide)
		if self.floats then
			local bcp = pos:offset(0, -0.7, 0):round()
			local bcn = get_node(bcp)

			local bcd = core.registered_nodes[bcn.name]
			if bcd and bcd.liquidtype ~= "none" then
				if self:try_place(bcp, bcn) then
					self.object:remove()
					return
				end
			end
		end

		--  check if falling node has custom function set
		local custom = core.registered_items[self.node.name]
				and core.registered_items[self.node.name].falling_step

		if custom and custom(self, pos, dtime) == false then
			return -- skip further checks if false
		end

		assert(moveresult)
		if not moveresult.collides then
			return -- Nothing to do :)
		end

		local bcp, bcn
		local player_collision, object_collision
		if moveresult.touching_ground then
			for _, info in ipairs(moveresult.collisions) do
				if info.type == "object" then
					if info.axis == "y" then
						if info.object:is_player() then
							player_collision = info
						else
							object_collision = info
						end
					end
				elseif info.axis == "y" then
					bcp = info.node_pos
					bcn = get_node(bcp)
					break
				end
			end
		end

		if not bcp then
			-- We're colliding with something, but not the ground. Irrelevant to us.
			if player_collision then

				fall_hurt_check(self, player_collision.object)

				-- Continue falling through players by moving a little into
				-- their collision box
				-- TODO: this hack could be avoided in the future if objects
				--       could choose who to collide with
				local vel = self.object:get_velocity()
				self.object:set_velocity(vector.new(
					vel.x,
					player_collision.old_velocity.y,
					vel.z
				))
				self.object:set_pos(self.object:get_pos():offset(0, -0.5, 0))
			elseif object_collision then
				fall_hurt_check(self, object_collision.object)
			end
			return
		elseif bcn.name == "ignore" then
			-- Delete on contact with ignore at world edges
			self.object:remove()
			return
		end

		local failure = false

		local pos = self.object:get_pos()
		local distance = vector.apply(vector.subtract(pos, bcp), math.abs)
		if distance.x >= 1 or distance.z >= 1 then
			-- We're colliding with some part of a node that's sticking out
			-- Since we don't want to visually teleport, drop as item
			failure = true
		elseif distance.y >= 2 then
			-- Doors consist of a hidden top node and a bottom node that is
			-- the actual door. Despite the top node being solid, the moveresult
			-- almost always indicates collision with the bottom node.
			-- Compensate for this by checking the top node
			bcp.y = bcp.y + 1
			bcn = get_node(bcp)
			local def = core.registered_nodes[bcn.name]
			if not (def and def.walkable) then
				failure = true -- This is unexpected, fail
			end
		end

		-- Try to actually place ourselves
		if not failure then
			failure = not self:try_place(bcp, bcn)
		end

		if failure then
			local drops = core.get_node_drops(self.node, "")
			for _, item in pairs(drops) do
				core.add_item(pos, item)
			end
		end
		self.object:remove()
	end
})

-- what's called when you place/punch/dig something

local falling_neighbors = {
	vector.new(-1, -1,  0), vector.new( 1, -1,  0), vector.new( 0, -1, -1),
	vector.new( 0, -1,  1), vector.new( 0, -1,  0), vector.new(-1,  0,  0),
	vector.new( 1,  0,  0), vector.new( 0,  0,  1), vector.new( 0,  0, -1),
	vector.new( 0,  0,  0), vector.new( 0,  1,  0)
}

function core.check_for_falling(p)

	local stack = {vector.round(p)}
	local count = 0
	local max_depth = 650

	while #stack > 0 and count < max_depth do

		local current_pos = table.remove(stack) -- store and remove position

		count = count + 1

		for _, offset in ipairs(falling_neighbors) do

			local next_pos = vector.add(current_pos, offset)
			
			-- If node be falling, add to stack for a neighbor check
			if core.check_single_for_falling(next_pos) then

				table.insert(stack, next_pos)
				
				-- Incase of massive collapses
				if #stack + count > max_depth then return end
			end
		end
	end
end


--[[
core.override_item("default:gravel", {
	falling_step = function(self, pos, dtime)
		print ("Gravel falling!", dtime, self.node.name, self.meta, self.object:get_pos())
	end
})
]]


print("[MOD] Falling Item loaded")

