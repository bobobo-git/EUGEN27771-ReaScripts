--[[
   * ReaScript Name:SampleEditor
   * Lua script for Cockos REAPER
   * Author: EUGEN27771
   * Author URI: http://forum.cockos.com/member.php?u=50462
   * Licence: GPL v3
   * Version: 1.0
  ]]

local Wave = {} -- Main table
local Undo = {} -- For Undo data
-------------------------
-------------------------
-------------------------
function Wave:Get_Source()
   local Item, Take, Source, Source_type
      ------------------------------------------------------------------
      Item = reaper.GetSelectedMediaItem(0, 0)
      if Item   then Take = reaper.GetActiveTake(Item) else  return  false, "No Selected Items!"  end 
      if Take   then Source = reaper.GetMediaItemTake_Source(Take) else  return  false, "Empty item!" end
      if Source then Source_type = reaper.GetMediaSourceType(Source,"") end
      -- Fix in future for section ??? --
      --[[if Source_type=="SECTION" then Source_type = reaper.GetMediaSourceParent(Source)
             reaper.MB("Sec,fix in future","Info", 0) return 
          end
          local ret, src_offs, src_len, src_rev = reaper.PCM_Source_GetSectionInfo(Source) -- Source_GetSectionInfo,need in future
        ]] 
      ------------------------------------------------------------------
      if Source_type~="WAVE" then return  false, "Invalide Type - "..Source_type end
      ------------------------------------------------------------------
      -- Read data from wav file ---------------------------------------
      ------------------------------------------------------------------
      local FilePath  = reaper.GetMediaSourceFileName(Source , "") -- Source FilePath
      local file = io.open(FilePath,"rb")  -- open file, rb mode
      if not file then return false, "File not available!"  end -- if not available 
      local Data = file:read("*a")         -- read(all)
      file:close()                         -- close file
      --------------------------------------------------------
      --------------------------------------------------------
      local chunkSize     = string.unpack("<I4", Data:sub(5,8))
      local subchunk1Size = string.unpack("<I4", Data:sub(17,20))
      local audioFormat   = string.unpack("<I2", Data:sub(21,22))
      local nchans        = string.unpack("<I2", Data:sub(23,24))
      local srate         = string.unpack("<I4", Data:sub(25,28))
      local byterate      = string.unpack("<I4", Data:sub(29,32))
      local blockalign    = string.unpack("<I2", Data:sub(33,34))
      local bitspersample = string.unpack("<I2", Data:sub(35,36))
        -- If format not supported -----------------------------
        if     audioFormat==1 and (bitspersample==16 or bitspersample==24) then  -- true format
        elseif audioFormat==3 and (bitspersample==32 or bitspersample==64) then  -- true format
        else return  false, "Not supported - ".."format "..audioFormat..", "..bitspersample.."bit"
        end
      ---------------------------------------------------------- 
      local i,j = Data:find("data")  -- find "data" in file
      local subchunk2Size = string.unpack("<I4", Data:sub(j+1,j+4)) -- data size(in bytes)
      local Datablock = j+5          -- Its Datablock start -  1-based !!!
      --- Check data(info) ---------------------------------------------
      --[[
      reaper.ShowConsoleMsg("audioFormat = "..audioFormat.."\n"..
                            "nchans = "..nchans.."\n"..
                            "bitspersample = "..bitspersample.."\n"..
                            "srate = "..srate.."\n"..
                            "blockalign = "..blockalign.."\n"..
                            "bitspersample = "..bitspersample.."\n"..
                            "data size(in bytes) = "..subchunk2Size.."\n"..
                            "Datablock start(1-based) = "..Datablock.."\n")  --]] 
      --------------------------------------------------------------------------------------------------------
      -- Calculate Time Selection range ----------------------------------------------------------------------
      --------------------------------------------------------------------------------------------------------
      local sel_start, sel_end = reaper.GetSet_LoopTimeRange(false,false,0,0,false) -- time-sel start, end
      if (sel_end - sel_start)==0 then return false, "No selection!" end
      ------------------------------------
      -- Item start, len, end info -------
      local Item_start, Item_len, Item_end
      Item_start = reaper.GetMediaItemInfo_Value(Item,'D_POSITION')
      Item_len   = reaper.GetMediaItemInfo_Value(Item,'D_LENGTH')
      Item_end   = Item_start + Item_len
      ------------------------------------
      -- Time Sel to Item time -----------
      local sel_start_in_item, sel_end_in_item
      sel_start_in_item =  math.max( sel_start - Item_start,        0 )
      sel_end_in_item   =  math.min( sel_end   - Item_start, Item_len )
        -- if selection out of item ! ----
        if sel_start_in_item>=Item_len or sel_end_in_item<=0 then return false, "Selection out of Item!" end
      ------------------------------------
      -- Time Sel to Source time ---------
      local offset,playrate, source_len,lenIsQN, sel_start_in_source,sel_end_in_source 
      offset   = reaper.GetMediaItemTakeInfo_Value(Take, 'D_STARTOFFS')
      playrate = reaper.GetMediaItemTakeInfo_Value(Take, 'D_PLAYRATE')
      source_len, lenIsQN = reaper.GetMediaSourceLength(Source)
      sel_start_in_source = math.max( sel_start_in_item * playrate + offset , 0          )
      sel_end_in_source   = math.min( sel_end_in_item   * playrate + offset , source_len )
        -- if selection out of source ! --
        if sel_start_in_source>=source_len or sel_end_in_source<=0 then return false, "Selection out of Source!" end
        -- Limit Selection to 100ms(deliberate limitation) !!! --
        if sel_end_in_source - sel_start_in_source > 0.1 then sel_end_in_source = sel_start_in_source + 0.1 end
      ---------------------------------------------------------------------------
      ---------------------------------------------------------------------------
      -- Time Selection to item samples(use source srate and round inward sel) --
      ---------------------------------------------------------------------------
      local sel_start_in_smpls, sel_end_in_smpls, sel_range_in_smpls
      sel_start_in_smpls = math.ceil(sel_start_in_source * srate) + 1 -- in samples, 1-based !!!
      sel_end_in_smpls   = math.floor(sel_end_in_source  * srate) + 1 -- in samples, 1-based !!!
      sel_end_in_smpls   = math.min(sel_end_in_smpls, subchunk2Size/blockalign) -- verify sel_end
      sel_range_in_smpls = sel_end_in_smpls - sel_start_in_smpls + 1 -- sel range to samples !!!
        -- if selection < 2 smpls ! ------
        if sel_range_in_smpls<2 then return false, "Selection < 2 smpls" end
      
      --------------------------------------------------------------------------------------------------------
      --------------------------------------------------------------------------------------------------------
      -- Simple scheme   ||1 -- |D1 (processed part) -- |D2 -- ||   ------------------------------------------
      --------------------------------------------------------------------------------------------------------
      local  D1, D2
      D1 = Datablock +  (sel_start_in_smpls-1) * blockalign -- Start_Byte
      D2 = D1 +  sel_range_in_smpls * blockalign 
      -------------------------------------------------------
      local Data1,SMPLS,Data2 
      Data1 = Data:sub(1,  D1 - 1) -- ||1 -- |
      SMPLS = Data:sub(D1, D2 - 1) -- |D1 (processed part) -- |
      Data2 = Data:sub(D2)         -- |D2 -- ||
      -----------------------------------------------------------------------------------
      -- Get samples --------------------------------------------------------------------
      -----------------------------------------------------------------------------------
      local buf = {} -- Its sample buffer!
      local Pfmt,Bps -- Pack format, BYTES per sample ------
        if bitspersample==16 then Pfmt = "<i2"; Bps = 2 end
        if bitspersample==24 then Pfmt = "<i3"; Bps = 3 end
        if bitspersample==32 then Pfmt = "<f" ; Bps = 4 end
        if bitspersample==64 then Pfmt = "<d" ; Bps = 8 end
      ------------------------------------------------------
      -- Unpuck values -------------------------------------
      ------------------------------------------------------
      local b=1
      for i=1, sel_range_in_smpls*nchans do
          buf[i] = string.unpack(Pfmt, SMPLS:sub(b, b+Bps-1) ) -- val to buffer 
          b = b+Bps 
      end
    ---------------------------------------------------------------------
    -- Define self values  ----------------------------------------------
    ---------------------------------------------------------------------
    self.Item  = Item
    self.Take  = Take
    self.FilePath  = FilePath
    self.nchans    = nchans
    self.srate     = srate
    self.sel_range_in_smpls = sel_range_in_smpls
    self.bitspersample = bitspersample 
    self.Data1 = Data1
    self.Data2 = Data2
    self.buf   = buf
    self.Pfmt  = Pfmt
    self.Bps   = Bps
    -------------------------------
    -- Info For Undo  -------------
    -------------------------------
    self.D1 = D1       -- D1 point
    self.D2 = D2       -- D2 point
    self.SMPLS = SMPLS -- Original SMPLS part
  return true    
end

--------------------------------------------------------------------------------
--   Draw   --------------------------------------------------------------------
--------------------------------------------------------------------------------
function Wave:Draw_Samples(chan, Wx,Wy,Ww,Wh, r,g,b,a)
    local Ay = Wy + Wh/2 -- axis y-coord 
    local Srds = 2       -- sample "point" radius
    -------------------
    local Sx,Sy,Srng -- Sx,Sy = x,y smpl scales in gfx, Srng = smpl Value range
      if self.Pfmt == "<f" or self.Pfmt == "<d" then Srng = 1 else Srng = 2^(self.bitspersample-1) end
      Sx = (Ww/(self.sel_range_in_smpls-1)) /self.nchans
      Sy = (Wh/2) /Srng * V_Zoom 
    -- Draw axis -------
    gfx.set(0.7,0.7,0.6,0.7)
    gfx.line(Wx, Ay, Wx+Ww, Ay, true) 
     ------------------------------------------
     -- Draw Samples(and get mouse) -----------
     ------------------------------------------
     gfx.set(r,g,b,a)
     local x,y,x2,y2
     for i=chan, #self.buf, self.nchans do
         x = Wx + (i-chan)*Sx -- sample x-position 
         --------------------------------------
         -- Get mouse -------------------------
         if gfx.mouse_cap&1==1 and math.abs(gfx.mouse_x - x)<= math.max(Sx*self.nchans/2, 5) and 
            mouse_oy>=Wy and mouse_oy<=Wy+Wh  then local smpl = (Ay - gfx.mouse_y)/Sy
              -- valid value --
              if self.Pfmt == "<i2" or self.Pfmt == "<i3" then smpl = math.floor(smpl + 0.5)
                  if smpl>Srng-1 then smpl = Srng-1 elseif smpl< -Srng then smpl = -Srng end -- valid 16,24 smpl range
              elseif self.Pfmt == "<f" or self.Pfmt == "<d" then
                  if smpl>1      then smpl = 1      elseif smpl< -1    then smpl = -1    end -- valid 32 smpl range
              end
            self.buf[i] = smpl -- to buffer
         end 
           ---------------------------------------
           -- Draw sample Point ------------------
           local Vy = self.buf[i]*Sy -- sample "y-value"
             if Vy>0 and Vy>Wh/2 then Vy = Wh/2 
             elseif Vy<0 and Vy<-Wh/2 then Vy = -Wh/2 
             end
           y = Ay - Vy               -- sample y-position 
           ---------------------------------------
           if self.sel_range_in_smpls<256 then gfx.circle(x,y,Srds,true,true) end
           ---------------------------------------
           -- Draw line = current-next sample ----
           if i < #self.buf-self.nchans+chan then
              x2 = Wx + Wx + (i-chan+self.nchans)*Sx -- next sample x-position
              local Vy2 = self.buf[i+self.nchans]*Sy -- next sample "y-value"
                 if Vy2>0 and Vy2>Wh/2 then Vy2 = Wh/2 
                 elseif Vy2<0 and Vy2<-Wh/2 then Vy2 = -Wh/2 
                 end
              y2 = Ay - Vy2                          -- next sample y-position
              gfx.line(x,y,x2,y2,true)
           end
     end
end

----------------------------------------------------------------------------------
--- Rewrite_Wave_File ------------------------------------------------------------
----------------------------------------------------------------------------------
function Wave:Rewrite_File()
 -----------------------------------------------------------
 -- Offline,Online media and Rebuild peaks action IDs  -----
 -----------------------------------------------------------
 local OfflineID,OnlineID = 40100,40101   -- 40100,40101 = ALL; 40440,40439 = SELECTED Items
 local RebuildID = 40047 -- 40047 = MISSING(Optimally); 40441 = SELECTED; 40048 = ALL  Peaks
 ---------------------------------------------------
    ------------------------------------------------
    --- Open File ----------------------------------
    ------------------------------------------------
    local file
    if self.buf and self.FilePath then 
       reaper.Main_OnCommand(OfflineID, 0) -- Offline media item
       file = io.open(self.FilePath,"wb")  -- Open file in "wb"
         -- if file not aviable --
         if not file then reaper.Main_OnCommand(OnlineID, 0) -- Online media item
            return reaper.MB("File Not aviable for write!", "Info", 0)
         end
    end
    ---------------------------------------------------
    --- Buffer_to_chars -------------------------------
    --------------------------------------------------- 
    local Data_buf = {} 
    -- Puck values  -----
    for i=1, #self.buf do
        Data_buf[i] = string.pack(self.Pfmt, self.buf[i]) -- little-endian
    end    
    ---------------------------------------------------
    -- Concat Data table  -----------------------------
    ---------------------------------------------------  
    local Data = table.concat(Data_buf) -- Concat(Its wave Data!!!)  
    ---------------------------
    -- Write Data to file -----
    ---------------------------
    file:write(self.Data1,Data,self.Data2)
    file:close()
    ---------------------------------------------------
    -- Online media, Rebuild peaks, Update ------------
    ---------------------------------------------------
    reaper.Main_OnCommand(OnlineID, 0)    -- Online media item
    reaper.Main_OnCommand(RebuildID, 0)   -- Rebuild peaks after changes  
    reaper.UpdateItemInProject(self.Item) -- Just in case, not necessarily
    reaper.UpdateArrange()                -- Update Arrange
end
--------------------------------------------------------------------------------
--  Create Undo point   --------------------------------------------------------
--------------------------------------------------------------------------------
function Create_Undo_Point()
    local UndoPoint = {FilePath = Wave.FilePath,
                       D1 = Wave.D1, 
                       D2 = Wave.D2,
                       SMPLS = Wave.SMPLS}
    table.insert(Undo, UndoPoint) -- insert UndoPoint to Undo table
end
--------------------------------------------------------------------------------
--  UNDO   ---------------------------------------------------------------------
--------------------------------------------------------------------------------
function Apply_UNDO()
  local UndoPoint
  local Pn = #Undo -- Last UndoPoint in Undo table
  if Pn>0 then UndoPoint = Undo[Pn] else return reaper.MB("No Undo Points!" , "Info", 0) end
  local FilePath = UndoPoint.FilePath
  local D1 = UndoPoint.D1
  local D2 = UndoPoint.D2
  local SMPLS = UndoPoint.SMPLS
    --------------------------------------------------------
    -- Open File, Read Data1, Data2 ------------------------
    --------------------------------------------------------
    local file = io.open(FilePath,"rb")  -- open file, rb mode
    if not file then return reaper.MB("File Not aviable!", "Info", 0) end -- if not available 
    local Data = file:read("*a")         -- read(all)
    file:close()                         -- close file
    ------------------------------------------------
    local Data1, Data2 
    Data1 = Data:sub(1, D1 - 1)  -- ||1 -- |
    Data2 = Data:sub( D2)        -- |D2 -- ||
    ------------------------------------------------
    --- Open File for Write ------------------------
    ------------------------------------------------
    local OfflineID,OnlineID = 40100,40101   -- 40100,40101 = ALL; 40440,40439 = SELECTED Items
    local RebuildID = 40047 -- 40047 = MISSING(Optimally); 40441 = SELECTED; 40048 = ALL  Peaks
    -----------------------------------------------
    reaper.Main_OnCommand(OfflineID, 0) -- Offline media items
    file = io.open( FilePath,"wb")      -- Open file in "wb"
     -- if file not aviable --
     if not file then reaper.Main_OnCommand(OnlineID, 0) -- Online media item
        return reaper.MB("File Not aviable for write!", "Info", 0)
     end
    --------------------------------
    -- Write Undo Data to file -----
    --------------------------------
    file:write(Data1,  SMPLS, Data2)
    file:close()
    ---------------------------------------------------
    -- Online media, Rebuild peaks, Update ------------
    ---------------------------------------------------
    reaper.Main_OnCommand(OnlineID, 0)    -- Online media item
    reaper.Main_OnCommand(RebuildID, 0)   -- Rebuild peaks after changes  
    reaper.UpdateArrange()                -- Update Arrange
  --------------------------------------------------------
  --------------------------------------------------------
  table.remove(Undo) -- Remove Last Undo Point 
end
--------------------------------------------------------------------------------
--   Proj_Change   -------------------------------------------------------------
--------------------------------------------------------------------------------
function Proj_Change()
    local cur_cnt = reaper.GetProjectStateChangeCount(0)
    if not Proj_Change_cnt or cur_cnt ~= Proj_Change_cnt then
       Proj_Change_cnt = cur_cnt
       return true  
    end
end
--------------------------------------------------------------------------------
--   INIT   --------------------------------------------------------------------
--------------------------------------------------------------------------------
function Init()
    -- Some gfx Wnd Default Values ---------------
    local R,G,B = 20,20,20              -- 0...255 format
    local Wnd_bgd = R + G*256 + B*65536 -- red+green*256+blue*65536  
    local Wnd_Title = "Sample Editor b2"
    local Wnd_Dock,Wnd_X,Wnd_Y = 0,100,320 
    Wnd_W,Wnd_H = 1044,490 -- global values(used for define zoom level)
    -- Init window ------
    gfx.clear = Wnd_bgd         
    gfx.init( Wnd_Title, Wnd_W,Wnd_H, Wnd_Dock, Wnd_X,Wnd_Y )
    -- Init mouse last --
    last_mouse_cap = 0
    last_x, last_y = 0, 0
    mouse_ox, mouse_oy = -1, -1
    V_Zoom = 1 --Vertical zoom level
end
----------------------------------------
--   Mainloop   ------------------------
----------------------------------------
function mainloop()
    -- zoom level -- 
    Z_w, Z_h = gfx.w/Wnd_W, gfx.h/Wnd_H
    if Z_w<0.6 then Z_w = 0.6 elseif Z_w>2 then Z_w = 2 end 
    if Z_h<0.6 then Z_h = 0.6 elseif Z_h>2 then Z_h = 2 end 
    -- mouse and modkeys --
    if gfx.mouse_cap&1==1   and last_mouse_cap&1==0  or   -- L mouse
       gfx.mouse_cap&2==2   and last_mouse_cap&2==0  or   -- R mouse
       gfx.mouse_cap&64==64 and last_mouse_cap&64==0 then -- M mouse
       mouse_ox, mouse_oy = gfx.mouse_x, gfx.mouse_y 
    end
    Ctrl  = gfx.mouse_cap&4==4   -- Ctrl  state
    Shift = gfx.mouse_cap&8==8   -- Shift state
    Alt   = gfx.mouse_cap&16==16 -- Shift state
    -------------------------
    if Proj_Change() then W,msg = Wave:Get_Source() end
    -------------------------
    -- DRAW,MAIN functions --
    -------------------------
    if W==true then
       local Wh = gfx.h/Wave.nchans
       local r,g,b,a = 0.7,0.5,0.6,1
       for chan=1, Wave.nchans do
           gfx.set(0.4,0.7,0.3,0.7)
           gfx.line(0,Wh*chan, gfx.w, Wh*chan, true)
           Wave:Draw_Samples(chan, 0,  Wh*(chan-1),  gfx.w, Wh, r,g,b,a) -- chan, Wx,Wy,Ww,Wh 
           r,g = g,r -- reverse r,g  
       end
    else gfx.setfont(1,"Arial", 25); gfx.set(0.8,0.7,0.5,1); gfx.x=20; gfx.y=20; gfx.drawstr(msg)
    end
    --------------------------
    --- Mouse L - Edit -------
     if gfx.mouse_cap&1==0 and last_mouse_cap&1==1 then
        Create_Undo_Point() -- Create Undo Point 
        Wave:Rewrite_File() -- Apply Changes to file
     end
    --------------------------
    --- Mouse R - Undo -------
    if gfx.mouse_cap&2==0 and last_mouse_cap&2==2 then Apply_UNDO() end -- Undo
    --------------------------
    --- M_Wheel - Vert Zoom --
    if gfx.mouse_wheel~=0 and not(Ctrl or Shift) then 
       local M_Wheel = gfx.mouse_wheel; gfx.mouse_wheel = 0
        if     M_Wheel>0 then V_Zoom = math.min(V_Zoom*1.2, 50) 
        elseif M_Wheel<0 then V_Zoom = math.max(V_Zoom*0.8, 1) 
        end 
    end
    --------------------------
    last_mouse_cap = gfx.mouse_cap
    last_x, last_y = gfx.mouse_x, gfx.mouse_y
    char = gfx.getchar() 
    if char==32 then reaper.Main_OnCommand(40044, 0) end -- play
    if char~=-1 then reaper.defer(mainloop) end          -- defer       
    -----------  
    gfx.update()
    -----------
end
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
Init()
mainloop()