--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2018 Peter Vaiko

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

---@class CoursePlot : CpObject
CoursePlot = CpObject()

-- Position and size of the course plot as normalized screen coordinates
-- x = 0, y = 0 is the bottom left corner of the screen, terrainSize is in meters
function CoursePlot:init()
	self.courseOverlayId = createImageOverlay('dataS/scripts/shared/graph_pixel.dds')
	self.startSignOverlayId = createImageOverlay(Utils.getFilename('img/signs/start_noMM.dds', Courseplay.BASE_DIRECTORY))
	self.stopSignOverlayId = createImageOverlay(Utils.getFilename('img/signs/stop_noMM.dds', Courseplay.BASE_DIRECTORY))
	self.startPosition = {}
	self.stopPosition = {}
	self.isVisible = false
	-- the normal FS22 blue
	self.color = {CpGuiUtil.getNormalizedRgb(42, 193, 237)}
	-- a lighter shade of the same color
	self.lightColor = {CpGuiUtil.getNormalizedRgb(45, 207, 255)}
	-- a darker shade of the same color
	self.darkColor = {CpGuiUtil.getNormalizedRgb(19, 87, 107)}
	self.lineThickness = 2 / g_screenHeight -- 2 pixels
end

function CoursePlot:delete()
	if self.courseOverlayId ~= 0 then
		delete(self.courseOverlayId)
	end
	if self.startSignOverlayId ~= 0 then
		delete(self.startSignOverlayId)
	end
end

function CoursePlot:setVisible( isVisible )
	self.isVisible = isVisible
end

function CoursePlot:setWaypoints( waypoints )
	self.waypoints = {}
	-- remove waypoints from long straight lines, the plot only needs start/end. Too many waypoints
	-- in the plot are a performance problem
	table.insert(self.waypoints, waypoints[1])
	self.waypoints[1].progress = 1 / #waypoints
	for i = 2, #waypoints - 1 do
		if waypoints[i].angle == nil or math.abs(waypoints[i].angle - waypoints[i - 1].angle) > 2 then
			table.insert(self.waypoints, waypoints[i])
			self.waypoints[#self.waypoints].progress = i / #waypoints
		end
	end
	table.insert(self.waypoints, waypoints[#waypoints])
	self.waypoints[1].progress = 1
	self:setStartPosition(self.waypoints[1].x, self.waypoints[1].z)
	self:setStopPosition(self.waypoints[#self.waypoints].x, self.waypoints[#self.waypoints].z)
end

-- start position used when generating the course, either first course wp
-- or the position selected by the user on the map. We'll show a sign there.
function CoursePlot:setStartPosition( x, z )
	self.startPosition.x, self.startPosition.z = x, z
end

-- end position of the course
function CoursePlot:setStopPosition( x, z )
	self.stopPosition.x, self.stopPosition.z = x, z
end

function CoursePlot:worldToScreen(map, worldX, worldZ, isHudMap)
	local objectX = (worldX + map.worldCenterOffsetX) / map.worldSizeX * 0.5 + 0.25
	local objectZ = (worldZ + map.worldCenterOffsetZ) / map.worldSizeZ * 0.5 + 0.25
	local x, y, _, _ = map.fullScreenLayout:getMapObjectPosition(objectX, objectZ, 0, 0, 0, true)
	local rot = 0
	local visible = true
	if isHudMap then 
		--- The plot is displayed in the hud.
		objectX = (worldX + map.worldCenterOffsetX) / map.worldSizeX * map.mapExtensionScaleFactor + map.mapExtensionOffsetX
		objectZ = (worldZ + map.worldCenterOffsetZ) / map.worldSizeZ * map.mapExtensionScaleFactor + map.mapExtensionOffsetZ

		x, y, rot, visible = map.layout:getMapObjectPosition(objectX, objectZ, 0, 0, 0, false)
		if map.state == IngameMap.STATE_MINIMAP_ROUND and map.layout.rotateWithMap then 
			x, y, rot, visible = self:getMapObjectPositionCircleLayoutFix(map.layout, objectX, objectZ, 0, 0, 0, false)
		end
	end
	return x, y, rot, visible
end

--- Giants was not so kind, as to allow getting the positions even, if the object is outside the map range ...
--- This is a custom version for: IngameMapLayoutCircle:getMapObjectPosition(...)
function CoursePlot:getMapObjectPositionCircleLayoutFix(layout, objectU, objectV, width, height, rot, persistent)
	local mapWidth, mapHeight = layout:getMapSize()
	local mapX, mapY = layout:getMapPosition()
	local objectX = objectU * mapWidth + mapX
	local objectY = (1 - objectV) * mapHeight + mapY
	objectX, objectY, rot = layout:rotateWithMap(objectX, objectY, rot, persistent)
	objectX = objectX - width * 0.5
	objectY = objectY - height * 0.5

	return objectX, objectY, rot, true
end

function CoursePlot:screenToWorld( x, y )
	local worldX = ((x - self.x) / self.scaleX) - self.worldOffsetX
	local worldZ = ((y - self.y - self.height) / -self.scaleZ) - self.worldOffsetZ
	return worldX, worldZ
end

-- Draw the waypoints in the screen area defined in new(), the bottom left corner
-- is at worldX/worldZ coordinates, the size shown is worldWidth wide (and high)
function CoursePlot:drawPoints(map, isHudMap)
	local lineThickness = self.lineThickness
	if isHudMap then 
		lineThickness = lineThickness/2
	end
	local mapRotation = map.layout:getMapRotation()
	if self.waypoints and #self.waypoints > 1 then
		-- I know this is in helpers.lua already but that code has too many dependencies
		-- on global variables and vehicle.cp.
		local wp, np, startX, startY, endX, endY, dx, dz, dx2D, dy2D, width, rotation, r, g, b, sv, ev
		-- render a line between subsequent waypoints
		for i = 1, #self.waypoints - 1 do
			wp = self.waypoints[ i ]
			np = self.waypoints[ i + 1 ]

			startX, startY, _, sv = self:worldToScreen(map, wp.x, wp.z, isHudMap)
			endX, endY, _, ev = self:worldToScreen(map, np.x, np.z, isHudMap)
	
			-- render only if it is on the plot area
			if startX and startY and endX and endY then
				dx2D = endX - startX
				dy2D = ( endY - startY ) / g_screenAspectRatio
				width = MathUtil.vector2Length(dx2D, dy2D)

				dx = np.x - wp.x
				dz = np.z - wp.z
				rotation = MathUtil.getYRotationFromDirection(dx, dz) - math.pi * 0.5 + mapRotation
				r, g, b = MathUtil.vector3ArrayLerp(self.lightColor, self.darkColor, wp.progress)
				setOverlayColor( self.courseOverlayId, r, g, b, 0.8 )
				setOverlayRotation( self.courseOverlayId, rotation, 0, 0 )
				renderOverlay( self.courseOverlayId, startX, startY, width, lineThickness )
			end
		end
		setOverlayRotation( self.courseOverlayId, 0, 0, 0 ) -- reset overlay rotation
	end
end


function CoursePlot:draw(map, isHudMap)

	if not self.isVisible then return end

	self:drawPoints(map, isHudMap)

	-- render the start and stop signs

	local signSizeMeters = 0.02
	local zoom = isHudMap and map.layout:getIconZoom() or map.fullScreenLayout:getIconZoom()
	if isHudMap and map.state == IngameMap.STATE_MAP then 
		--- When the hud is completely open, then the signs need to be scaled down.
		zoom = zoom * 0.5
	end
	local signWidth, signHeight = signSizeMeters * map.uiScale * zoom, signSizeMeters * map.uiScale * zoom * g_screenAspectRatio

	-- render a sign marking the end of the course
	if self.stopPosition.x and self.stopPosition.z then
		local x, y, rotation = self:worldToScreen( map,self.stopPosition.x, self.stopPosition.z, isHudMap)
		if x and y then
			setOverlayColor( self.stopSignOverlayId, 1, 1, 1, 1 )
			renderOverlay( self.stopSignOverlayId,
				x - signWidth / 2, -- offset so the middle of the sign is on the stopping location
				y - signHeight / 2,
				signWidth, signHeight)
		end
	end

	-- render a sign marking the current position used as a starting location for the course
	if self.startPosition.x and self.startPosition.z then
		local x, y, rotation = self:worldToScreen(map, self.startPosition.x, self.startPosition.z, isHudMap)
		if x and y then
			setOverlayColor( self.startSignOverlayId, 1, 1, 1, 0.8 )
			renderOverlay( self.startSignOverlayId,
				x - signWidth / 2, -- offset so the middle of the sign is on the starting location
				y - signHeight / 2,
				signWidth, signHeight)
		end
	end
end