/*	
 *	============================================================================
 *	
 *	[TF2] Custom Boss Spawner
 *	Alliedmodders: http://forums.alliedmods.net/member.php?u=87026
 *	Current Version: 4.2.1
 *
 *	This plugin is FREE and can be distributed to anyone.  
 *	If you have paid for this plugin, get your money back.
 *	
 *	Version Log:
 *	v.4.2.1_B2
 *	- Added args to !spawn <bossname> <health> <size:float> <glow:1,0>
 *	- Added args to !forceboss <bossname>
 *	v.4.2.1
 *	- Fixed TeleportLocation not working properly
 *	v.4.2
 *	- Changes: Now uses tries/hashmaps instead of multi-arrays
 *	- Changes: Skeleton king can now use custom model
 *	- Fixed call stack error onclientdisconnect timer
 * 	- Fixed issue with !spawn <boss> not spawning at users' cursor
 *	- Fixed small issue with spawn music playing twice
 *	- Fixed issue when unloading plugin does not remove admin spawned bosses
 *	- Added new type: tf_zombie which will spawn regular skeletons
 *	- Added new key: "Horde" which indicates how many skeletons to spawn
 *	- Added new key: "Color" which indicates which colors to set skeleton (blue,red,green,yellow,random)
 *	- Added new key: "IntroSound" which plays a custom sound when boss spawns
 *	- Added new key: "DeathSound" which plays a custom sound when boss dies
 *	- Added new key: "TeleportLocation" to bossspawner_maps.cfg which allows players to teleport to that location when monoculus/merasmus dies and spawns that thing that sucks you in
 *	- Updated translations and other reply messages w/ better colors
 *	
 *	============================================================================
 */
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <morecolors>

#define PLUGIN_VERSION "4.2.1"
#define INTRO_SND "ui/halloween_boss_summoned_fx.wav"
#define DEATH_SND "ui/halloween_boss_defeated_fx.wav"

new Handle:cVars[6] = 	{INVALID_HANDLE, ...};
new Handle:cTimer = 	INVALID_HANDLE;
new Handle:bTimer = 	INVALID_HANDLE;
new Handle:hHUD = 		INVALID_HANDLE;
new Handle:gArray = 	INVALID_HANDLE;
new Handle:gHArray = INVALID_HANDLE;

new sMode;
new Float:sInterval;
new Float:sMin;
new Float:sHUDx;
new Float:sHUDy;
new bool:gEnabled;

new gIndex = 0;
new gBoss = -1;
new Float:gPos[3];
new Float:kPos[3];
new bool:gActiveTimer;
new bool:gQueue;
new gBCount = 0;
new gTrack = -1;
new gHPbar = -1;
new gIndexCmd;
new gZSent;
new arg_index = 0;
new skele_index = 0;

public Plugin:myinfo =  {
	name = "[TF2] Custom Boss Spawner",
	author = "Tak (chaosxk)",
	description = "Spawns a custom boss with or without a timer.",
	version = PLUGIN_VERSION,
	url = "http://www.sourcemod.net"
}

public OnPluginStart() {
	cVars[0] = CreateConVar("sm_boss_version", PLUGIN_VERSION, "Halloween Boss Spawner Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	cVars[1] = CreateConVar("sm_boss_mode", "1", "What spawn mode should boss spawn? (0 - Random ; 1 - Ordered from HHH - Monoculus - Merasmus");
	cVars[2] = CreateConVar("sm_boss_interval", "300", "How many seconds until the next boss spawns?");
	cVars[3] = CreateConVar("sm_boss_minplayers", "12", "How many players are needed before enabling auto-spawning?");
	cVars[4] = CreateConVar("sm_boss_hud_x", "0.05", "X-Coordinate of the HUD display.");
	cVars[5] = CreateConVar("sm_boss_hud_y", "0.05", "Y-Coordinate of the HUD display");

	RegAdminCmd("sm_getcoords", GetCoords, ADMFLAG_GENERIC, "Get the Coordinates of your cursor.");
	RegAdminCmd("sm_forceboss", ForceSpawn, ADMFLAG_GENERIC, "Forces a boss to spawn");
	RegAdminCmd("sm_slayboss", SlayBoss, ADMFLAG_GENERIC, "Forces a boss to die");
	RegAdminCmd("sm_reloadbossconfig", ReloadConfig, ADMFLAG_GENERIC, "Reloads the map setting config");
	RegAdminCmd("sm_spawn", SpawnBossCommand, ADMFLAG_GENERIC, "Spawns a boss at the position the user is looking at.");

	HookEvent("teamplay_round_start", RoundStart);
	HookEvent("pumpkin_lord_summoned", Boss_Summoned, EventHookMode_Pre);
	HookEvent("pumpkin_lord_killed", Boss_Killed, EventHookMode_Pre);
	HookEvent("merasmus_summoned", Boss_Summoned, EventHookMode_Pre);
	HookEvent("merasmus_killed", Boss_Killed, EventHookMode_Pre);
	HookEvent("eyeball_boss_summoned", Boss_Summoned, EventHookMode_Pre);
	HookEvent("eyeball_boss_killed", Boss_Killed, EventHookMode_Pre);
	HookEvent("merasmus_escape_warning", Merasmus_Leave, EventHookMode_Pre);
	HookEvent("eyeball_boss_escape_imminent", Monoculus_Leave, EventHookMode_Pre);

	HookConVarChange(cVars[0], cVarChange);
	HookConVarChange(cVars[1], cVarChange);
	HookConVarChange(cVars[2], cVarChange);
	HookConVarChange(cVars[3], cVarChange);
	HookConVarChange(cVars[4], cVarChange);
	HookConVarChange(cVars[5], cVarChange);
	
	gArray = CreateArray();			//Array for storing boss attributes from a trie/hashmap
	gHArray = CreateArray();		//Array for horde mode
	
	LoadTranslations("common.phrases");
	LoadTranslations("bossspawner.phrases");
	AutoExecConfig(true, "bossspawner");
}

public OnPluginEnd() {
	RemoveExistingBoss();
	ClearTimer(cTimer);
	//reset flags for cheat cmds lifetime
	new flags = GetCommandFlags("tf_eyeball_boss_lifetime");
	SetCommandFlags("tf_eyeball_boss_lifetime", flags|FCVAR_CHEAT);
	flags = GetCommandFlags("tf_merasmus_lifetime");
	SetCommandFlags("tf_merasmus_lifetime", flags|FCVAR_CHEAT);	
}

public OnConfigsExecuted() {
	sMode = GetConVarInt(cVars[1]);
	sInterval = GetConVarFloat(cVars[2]);
	sMin = GetConVarFloat(cVars[3]);
	sHUDx = GetConVarFloat(cVars[4]);
	sHUDy = GetConVarFloat(cVars[5]);
	SetupMapConfigs("bossspawner_maps.cfg");
	if(gEnabled) {
		SetupBossConfigs("bossspawner_boss.cfg");
		FindHealthBar();
		PrecacheSound("items/cart_explode.wav");
	}
}

public RemoveBossLifeline(const String:command[], const String:execute[], duration) {
	new flags = GetCommandFlags(command); 
	SetCommandFlags(command, flags & ~FCVAR_CHEAT); 
	ServerCommand("%s %i", execute, duration);
	//SetCommandFlags(command, flags|FCVAR_CHEAT); 
}

public OnMapEnd() {
	RemoveExistingBoss();
	ClearTimer(cTimer);
}

public OnClientPostAdminCheck(client) {
	if(GetClientCount(true) == sMin) {
		if(gBCount == 0) {
			ResetTimer();
		}
	}
}

public OnClientDisconnect(client) {
	if(GetClientCount(true) < sMin) {
		RemoveExistingBoss();
		ClearTimer(cTimer);
	}
}

public cVarChange(Handle:convar, String:oldValue[], String:newValue[]) {
	if (StrEqual(oldValue, newValue, true))
		return;
	
	new Float:iNewValue = StringToFloat(newValue);

	if(convar == cVars[0])  {
		SetConVarString(cVars[0], PLUGIN_VERSION);
	}
	else if(convar == cVars[1]) {
		sMode = RoundFloat(iNewValue);
	}
	else if((convar == cVars[2]) || (convar == cVars[3])) {
		if(convar == cVars[2]) sInterval = iNewValue;
		else sMin = iNewValue;
		
		if(GetClientCount(true) >= sMin) {
			if(gBCount == 0) {
				ResetTimer();
			}
		}
		else {
			RemoveExistingBoss();
			ClearTimer(cTimer);
		}
	}
	else if(convar == cVars[4]) {
		sHUDx = iNewValue;
	}
	else if(convar == cVars[5]) {
		sHUDy = iNewValue;
	}
}

/* -----------------------------------EVENT HANDLES-----------------------------------*/
public Action:RoundStart(Handle:event, const String:name[], bool:dontBroadcast) {
	gBCount = 0;
	if(!gEnabled) return Plugin_Continue;
	ClearTimer(cTimer);
	if(GetClientCount(true) >= sMin) {
		if(gBCount == 0) {
			ResetTimer();
		}
	}
	return Plugin_Continue;
}

public Action:Boss_Summoned(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!gEnabled) return Plugin_Continue;
	new temp_index = gIndex;
	if(gActiveTimer == false) temp_index = gIndexCmd;
	else {
		if(sMode == 1) temp_index = gIndex == 0 ? GetArraySize(gArray)-1 : gIndex-1;
		else temp_index = gIndex;
	}
	decl String:sISound[256];
	new Handle:iTrie = INVALID_HANDLE;
	iTrie = GetArrayCell(gArray, temp_index);
	if(iTrie != INVALID_HANDLE) {
		GetTrieString(iTrie, "IntroSound", sISound, sizeof(sISound));
		EmitSoundToAll(sISound);
	}
	return Plugin_Handled;
}

public Action:Boss_Killed(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!gEnabled) return Plugin_Continue;
	new temp_index = gIndex;
	if(gActiveTimer == false) temp_index = gIndexCmd;
	else {
		if(sMode == 1) temp_index = gIndex == 0 ? GetArraySize(gArray)-1 : gIndex-1;
		else temp_index = gIndex;
	}
	decl String:sDSound[256];
	new Handle:iTrie = INVALID_HANDLE;
	iTrie = GetArrayCell(gArray, temp_index);
	if(iTrie != INVALID_HANDLE) {
		GetTrieString(iTrie, "DeathSound", sDSound, sizeof(sDSound));
		EmitSoundToAll(sDSound);
	}
	return Plugin_Handled;
}

public Action:Merasmus_Leave(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!gEnabled) return Plugin_Continue;
	return Plugin_Handled;
}

public Action:Monoculus_Leave(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!gEnabled) return Plugin_Continue;
	return Plugin_Handled;
}
/* -----------------------------------EVENT HANDLES-----------------------------------*/

/* ---------------------------------COMMAND FUNCTION----------------------------------*/

public Action:ForceSpawn(client, args) {
	if(!gEnabled) return Plugin_Handled;
	if(gBCount == 0) {
		if(args == 1) {
			skele_index = gIndex;
			decl String:arg1[32];
			GetCmdArg(1, arg1, sizeof(arg1));
			new i;
			for(i = 0; i < GetArraySize(gArray); i++) {
				decl String:sName[64];
				new Handle:iTrie = GetArrayCell(gArray, i);
				GetTrieString(iTrie, "Name", sName, sizeof(sName));
				if(StrEqual(sName, arg1, false)) {
					gIndex = i;
					break;
				}
			}
			PrintToChatAll("%d, %d", i, GetArraySize(gArray));
			if(i == GetArraySize(gArray)) {
				CReplyToCommand(client, "{frozen}[Boss] {red}Error: {orange}Boss does not exist.");
				return Plugin_Handled;
			}
			ClearTimer(cTimer);
			gActiveTimer = true;
			arg_index = 1;
			CreateBoss(gIndex, gPos, -1, -1, -1.0, -1, false);
		}
		else if(args == 0) {
			arg_index = 0;
			ClearTimer(cTimer);
			gActiveTimer = true;
			SpawnBoss(_,_,_);
		}
	}
	else {
		CReplyToCommand(client, "%t", "Boss_Active");
	}
	return Plugin_Handled;
}

public Action:GetCoords(client, args) {
	if(!gEnabled) return Plugin_Handled;
	if(!IsClientInGame(client) || !IsPlayerAlive(client)) {
		CReplyToCommand(client, "{frozen}[Boss] You must be alive and in-game to use this command.");
		return Plugin_Handled;
	}
	decl Float:l_pos[3];
	GetClientAbsOrigin(client, l_pos);
	CReplyToCommand(client, "{frozen}[Boss] {orange}Coordinates: %0.0f,%0.0f,%0.0f\n{frozen}[Boss] {orange}Use those coordinates and place them in configs/bossspawner_maps.cfg", l_pos[0], l_pos[1], l_pos[2]);
	return Plugin_Handled;
}

public Action:SlayBoss(client, args) {
	if(!gEnabled) {
		ReplyToCommand(client, "{frozen}[Boss] {orange}Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
	RemoveExistingBoss();
	CPrintToChatAll("%t", "Boss_Slain");
	return Plugin_Handled;
}

public Action:ReloadConfig(client, args) {
	ClearTimer(cTimer);
	SetupMapConfigs("bossspawner_maps.cfg");
	SetupMapConfigs("bossspawner_boss.cfg");
	CReplyToCommand(client, "{frozen}[Boss] {orange}Configs have been reloaded!");
}

public Action:SpawnBossCommand(client, args) {
	if(!gEnabled) return Plugin_Handled;
	if(!IsClientInGame(client) || !IsPlayerAlive(client)) {
		CReplyToCommand(client, "{frozen}[Boss] You must be alive and in-game to use this command.");
		return Plugin_Handled;
	}
	if(!SetTeleportEndPoint(client)) {
		CReplyToCommand(client, "{Frozen}[Boss] {orange}Could not find spawn point.");
		return Plugin_Handled;
	}
	if(args < 1) {
		CReplyToCommand(client, "{frozen}[Boss] {orange}Format: sm_spawn <{frozen}boss_name{orange}> <{frozen}health{orange}> <{frozen}size{orange}> <{frozen}glow{orange}>");
		return Plugin_Handled;
	}
	kPos[2] -= 10.0;
	decl String:arg1[32], String:arg2[32], String:arg3[32], String:arg4[32];
	GetCmdArg(1, arg1, sizeof(arg1));
	new i;
	new Handle:iTrie = INVALID_HANDLE;
	decl String:sName[64];
	for(i = 0; i < GetArraySize(gArray); i++) {
		iTrie = GetArrayCell(gArray, i);
		if(iTrie != INVALID_HANDLE) {
			GetTrieString(iTrie, "Name", sName, sizeof(sName));
			if(StrEqual(sName, arg1, false)){
				break;
			}
		}
	}
	if(i == GetArraySize(gArray)) {
		CReplyToCommand(client, "{frozen}[Boss] {red}Error: {orange}Boss does not exist.");
		return Plugin_Handled;
	}
	new iBaseHP = -1, Float:iSize = 1.0, iGlow = 0;
	if(args > 4) {
		CReplyToCommand(client, "{frozen}[Boss] {orange}Format: sm_spawn <{frozen}boss_name{orange}> <{frozen}health{orange}> <{frozen}size{orange}> <{frozen}glow{orange}>");
		return Plugin_Handled;
	}
	else {
		if(args > 1) {
			GetCmdArg(2, arg2, sizeof(arg2));
			iBaseHP = StringToInt(arg2);
		}
		if(args > 2) {
			GetCmdArg(3, arg3, sizeof(arg3));
			iSize = StringToFloat(arg3);
		}
		if(args > 3) {
			GetCmdArg(4, arg4, sizeof(arg4));
			iGlow = StringToInt(arg4);
		}
	}
	gIndexCmd = i;
	gActiveTimer = false;
	CreateBoss(gIndexCmd, kPos, iBaseHP, -1, iSize, iGlow, true);
	return Plugin_Handled;
}

SetTeleportEndPoint(client) {
	decl Float:vAngles[3];
	decl Float:vOrigin[3];
	decl Float:vBuffer[3];
	decl Float:vStart[3];
	decl Float:Distance;

	GetClientEyePosition(client,vOrigin);
	GetClientEyeAngles(client, vAngles);

	new Handle:trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceentFilterPlayer);

	if(TR_DidHit(trace)) {
		TR_GetEndPosition(vStart, trace);
		GetVectorDistance(vOrigin, vStart, false);
		Distance = -35.0;
		GetAngleVectors(vAngles, vBuffer, NULL_VECTOR, NULL_VECTOR);
		kPos[0] = vStart[0] + (vBuffer[0]*Distance);
		kPos[1] = vStart[1] + (vBuffer[1]*Distance);
		kPos[2] = vStart[2] + (vBuffer[2]*Distance);
	}
	else {
		CloseHandle(trace);
		return false;
	}

	CloseHandle(trace);
	return true;
}

public bool:TraceentFilterPlayer(ent, contentsMask) {
	return ent > GetMaxClients() || !ent;
}
/* ---------------------------------COMMAND FUNCTION----------------------------------*/

/* --------------------------------BOSS SPAWNING CORE---------------------------------*/
SpawnBoss(iBaseHP = -1, Float:iSize = -1.0, iGlow = -1) {
	new iScaleHP;
	if(iBaseHP != -1) {
		iScaleHP = 0;
	}
	gActiveTimer = true;
	if(sMode == 0) {
		gIndex = GetRandomInt(0, GetArraySize(gArray)-1);
		CreateBoss(gIndex, gPos, iBaseHP, iScaleHP, iSize, iGlow, false);
	}
	else if(sMode == 1) {
		gIndex++;
		CreateBoss(gIndex-1, gPos, iBaseHP, iScaleHP, iSize, iGlow, false);
		if(gIndex > GetArraySize(gArray)-1) gIndex = 0;
	}
}

public CreateBoss(index, Float:kpos[3], iBaseHP, iScaleHP, Float:iSize, iGlow, bool:isCMD) {
	new Float:temp[3];
	temp[0] = kpos[0];
	temp[1] = kpos[1];
	temp[2] = kpos[2];
	
	decl String:sName[64], String:sModel[256], String:sType[32], String:sBase[16], String:sScale[16];
	decl String:sSize[16], String:sGlow[8], String:sPosFix[32], String:sLifetime[32], String:sPosition[32], String:sHorde[8], String:sColor[16];
	//new BaseHP, ScaleHP, Size, Glow;
	new Handle:iTrie = GetArrayCell(gArray, index);
	GetTrieString(iTrie, "Name", sName, sizeof(sName));
	GetTrieString(iTrie, "Model", sModel, sizeof(sModel));
	GetTrieString(iTrie, "Type", sType, sizeof(sType));
	if(iBaseHP == -1) {
		GetTrieString(iTrie, "Base", sBase, sizeof(sBase));
		iBaseHP = StringToInt(sBase);
	}
	if(iScaleHP == -1) {
		GetTrieString(iTrie, "Scale", sScale, sizeof(sScale));
		iScaleHP = StringToInt(sScale);
	}
	if(iSize == -1.0) {
		GetTrieString(iTrie, "Size", sSize, sizeof(sSize));
		iSize = StringToFloat(sSize);
	}
	if(iGlow == -1) {
		GetTrieString(iTrie, "Glow", sGlow, sizeof(sGlow));
		iGlow = StrEqual(sGlow, "Yes") ? 1 : 0;
	}
	GetTrieString(iTrie, "PosFix", sPosFix, sizeof(sPosFix));
	GetTrieString(iTrie, "Lifetime", sLifetime, sizeof(sLifetime));
	GetTrieString(iTrie, "Position", sPosition, sizeof(sPosition));
	GetTrieString(iTrie, "Horde", sHorde, sizeof(sHorde));
	GetTrieString(iTrie, "Color", sColor, sizeof(sColor));
	if(!StrEqual(sPosition, NULL_STRING) && !isCMD) {
		decl String:sPos[3][16];
		ExplodeString(sPosition, ",", sPos, sizeof(sPos), sizeof(sPos[]));
		temp[0] = StringToFloat(sPos[0]);
		temp[1] = StringToFloat(sPos[1]);
		temp[2] = StringToFloat(sPos[2]);
	}
	temp[2] += StringToFloat(sPosFix);
	if(StrEqual(sType, "tf_zombie_spawner")) {
		new ent = CreateEntityByName(sType);
		if(IsValidEntity(ent)) {
			SetEntProp(ent, Prop_Data, "m_nSkeletonType", 1);
			TeleportEntity(ent, temp, NULL_VECTOR, NULL_VECTOR);
			DispatchSpawn(ent);
			gZSent = ent;
			gQueue = true;
			AcceptEntityInput(ent, "Enable");
		}
		EmitSoundToAll("ui/halloween_boss_summoned_fx.wav");
	}
	else if(StrEqual(sType, "tf_zombie")) {
		new count = StringToInt(sHorde);
		new playerCounter = GetClientCount(true);
		new sHealth = (iBaseHP + iScaleHP*playerCounter);
		//SetEntProp(entity, Prop_Send, "m_iTeamNum", team);
		for(new i = 0; i < count; i++) {
			new ent = CreateEntityByName(sType);
			if(IsValidEntity(ent)) {
				TeleportEntity(ent, temp, NULL_VECTOR, NULL_VECTOR);
				DispatchSpawn(ent);
				//SetEntityModel(ent, "models/bots/skeleton_sniper_boss/skeleton_sniper_boss.mdl");
				//SetEntProp(ent, Prop_Send, "m_nSkin", i);
				//gBoss = ent;
				SetEntProp(ent, Prop_Data, "m_iHealth", sHealth);
				SetEntProp(ent, Prop_Data, "m_iMaxHealth", sHealth);
				if(!StrEqual(sColor, NULL_STRING)) {
					if(StrEqual(sColor, "Red", false)) {
						SetEntProp(ent, Prop_Send, "m_nSkin", 0);
					}
					else if(StrEqual(sColor, "Blue", false)) {
						SetEntProp(ent, Prop_Send, "m_nSkin", 1);
					}
					else if(StrEqual(sColor, "Green", false)) {
						SetEntProp(ent, Prop_Send, "m_nSkin", 2);
					}
					else if(StrEqual(sColor, "Yellow", false)) {
						SetEntProp(ent, Prop_Send, "m_nSkin", 3);
					}
					else if(StrEqual(sColor, "Random", false)) {
						new rand = GetRandomInt(0, 3);
						SetEntProp(ent, Prop_Send, "m_nSkin", rand);
					}
				}
				if(!StrEqual(sModel, NULL_STRING)) {
					SetEntityModel(ent, sModel);
				}
				if(gActiveTimer == true) {
					gBCount++;
					PushArrayCell(gHArray, EntIndexToEntRef(ent));
				}
				SetSize(iSize, ent);
				SetGlow(iGlow, ent);
				//AcceptEntityInput(ent, "Enable");
			}
		}
		CPrintToChatAll("%t", "Boss_Spawn", sName);
		EmitSoundToAll("ui/halloween_boss_summoned_fx.wav");
		if(arg_index == 1) {
			gIndex = skele_index;
		}
	}
	else {
		new ent = CreateEntityByName(sType);
		if(IsValidEntity(ent)) {
			new playerCounter = GetClientCount(true);
			new sHealth = (iBaseHP + iScaleHP*playerCounter)*10;
			TeleportEntity(ent, temp, NULL_VECTOR, NULL_VECTOR);
			DispatchSpawn(ent);
			SetEntProp(ent, Prop_Data, "m_iHealth", sHealth);
			SetEntProp(ent, Prop_Data, "m_iMaxHealth", sHealth);
			if(StrEqual(sType, "eyeball_boss")) {
				SetEntProp(ent, Prop_Data, "m_iTeamNum", 5);
				//SetEntProp(ent, Prop_Data, "m_nSkin", 1);
			}
			//EmitSoundToAll("ui/halloween_boss_summoned_fx.wav");
			if(!StrEqual(sModel, NULL_STRING)) {
				SetEntityModel(ent, sModel);
			}
			if(gActiveTimer == true) {
				gBCount++;
				gBoss = ent;
				bTimer = CreateTimer(StringToFloat(sLifetime), RemoveTimer, index);
			}
			CPrintToChatAll("%t", "Boss_Spawn", sName);
			SetSize(iSize, ent);
			SetGlow(iGlow, ent);
		}
		if(arg_index == 1) {
			gIndex = skele_index;
		}
	}
}

public Action:RemoveTimer(Handle:hTimer, any:index) {
	if(IsValidEntity(gBoss)) {
		decl String:sName[64];
		new Handle:iTrie = GetArrayCell(gArray, index);
		GetTrieString(iTrie, "Name", sName, sizeof(sName));
		CPrintToChatAll("%t", "Boss_Left", sName);
		AcceptEntityInput(gBoss, "Kill");
	}
	return Plugin_Handled;
}

RemoveExistingBoss() {
	new ent = -1;
	while((ent = FindEntityByClassname(ent, "headless_hatman")) != -1) {
		if(IsValidEntity(ent)) {
			AcceptEntityInput(ent, "Kill");
		}
	}
	while((ent = FindEntityByClassname(ent, "eyeball_boss")) != -1) {
		if(IsValidEntity(ent)) {
			AcceptEntityInput(ent, "Kill");
		}
	}
	while((ent = FindEntityByClassname(ent, "merasmus")) != -1) {
		if(IsValidEntity(ent)) {
			AcceptEntityInput(ent, "Kill");
		}
	}
	while((ent = FindEntityByClassname(ent, "tf_zombie")) != -1) {
		if(IsValidEntity(ent)) {
			AcceptEntityInput(ent, "Kill");
		}
	}
}

SetGlow(value, ent) {
	if(IsValidEntity(ent)) {
		SetEntProp(ent, Prop_Send, "m_bGlowEnabled", value);
	}
}

SetSize(Float:value, ent) {
	if(IsValidEntity(ent)) {
		SetEntPropFloat(ent, Prop_Send, "m_flModelScale", value);
		ResizeHitbox(ent, value);
	}
}

//Taken from r3dw3r3w0lf
//Doesn't seem to work with skeleton/king
ResizeHitbox(entity, Float:fScale = 1.0) {
	decl Float:vecBossMin[3], Float:vecBossMax[3];	
	GetEntPropVector(entity, Prop_Send, "m_vecMins", vecBossMin);
	GetEntPropVector(entity, Prop_Send, "m_vecMaxs", vecBossMax);
	
	decl Float:vecScaledBossMin[3], Float:vecScaledBossMax[3];
	
	vecScaledBossMin = vecBossMin;
	vecScaledBossMax = vecBossMax;
	
	ScaleVector(vecScaledBossMin, fScale);
	ScaleVector(vecScaledBossMax, fScale);
	SetEntPropVector(entity, Prop_Send, "m_vecMins", vecScaledBossMin);
	SetEntPropVector(entity, Prop_Send, "m_vecMaxs", vecScaledBossMax);
}
/* --------------------------------BOSS SPAWNING CORE---------------------------------*/

/* ---------------------------------TIMER & HUD CORE----------------------------------*/
public HUDTimer() {
	if(!gEnabled) return;
	sInterval = GetConVarFloat(cVars[2]);
	if(hHUD != INVALID_HANDLE) {
		for(new i = 1; i <= MaxClients; i++) {
			if(IsClientInGame(i))
				ClearSyncHud(i, hHUD);
		}
		CloseHandle(hHUD);
	}
	hHUD = CreateHudSynchronizer();
	cTimer = CreateTimer(1.0, HUDCountDown, _, TIMER_REPEAT);
}

public Action:HUDCountDown(Handle:hTimer) {
	sInterval--;
	for(new i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			SetHudTextParams(sHUDx, sHUDy, 1.0, 255, 255, 255, 255);
			ShowSyncHudText(i, hHUD, "Boss: %d seconds", RoundFloat(sInterval));
		}
	}
	if(sInterval <= 0) {
		SpawnBoss(_,_,_);
		cTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

ResetTimer() {
	if(gBCount == 0) {
		CPrintToChatAll("%t", "Time", RoundFloat(sInterval));
		ClearTimer(cTimer);
		HUDTimer();
	}
}
/* ---------------------------------TIMER & HUD CORE----------------------------------*/

/* ---------------------------------ENTITY MANAGEMENT---------------------------------*/
public OnEntityCreated(ent, const String:classname[]) {
	if (StrEqual(classname, "monster_resource")) {
		gHPbar = ent;
	}
	else if(gTrack == -1 && (StrEqual(classname, "headless_hatman") || StrEqual(classname, "eyeball_boss") || StrEqual(classname, "merasmus"))) {
		gTrack = ent;
		SDKHook(ent, SDKHook_SpawnPost, UpdateBossHealth);
		SDKHook(ent, SDKHook_OnTakeDamagePost, OnBossDamaged);
	}
	if(StrEqual(classname, "prop_dynamic")) {
		RequestFrame(OnPropSpawn, EntIndexToEntRef(ent));
	}
	if(StrEqual(classname, "tf_zombie") && gQueue == true) {
		gTrack = ent;
		RequestFrame(OnSkeletonSpawn, EntIndexToEntRef(ent));
		SDKHook(ent, SDKHook_SpawnPost, UpdateBossHealth);
		SDKHook(ent, SDKHook_OnTakeDamagePost, OnBossDamaged);
	}
}

public OnEntityDestroyed(ent) {
	if(!gEnabled) return;
	if(IsValidEntity(ent) && ent > MaxClients) {
		decl String:classname[MAX_NAME_LENGTH];
		GetEntityClassname(ent, classname, sizeof(classname));
		if(ent == gBoss) {
			gBoss = -1;
			gBCount--;
			if(GetClientCount(true) >= sMin) {
				if(gBCount == 0) {
					HUDTimer();
					CPrintToChatAll("%t", "Time", RoundFloat(sInterval));
				}
			}
		}
		if(ent == gTrack) {
			gTrack = FindEntityByClassname(-1, "merasmus");
			if (gTrack == ent) {
				gTrack = FindEntityByClassname(ent, "merasmus");
			}
			if (gTrack > -1) {
				SDKHook(gTrack, SDKHook_OnTakeDamagePost, OnBossDamaged);
			}
			UpdateBossHealth(gTrack);
		}
		for(new i = 0; i < GetArraySize(gHArray); i++) {
			if(EntRefToEntIndex(GetArrayCell(gHArray, i)) == ent) {
				gBCount--;
				if(GetClientCount(true) >= sMin) {
					if(gBCount == 0) {
						HUDTimer();
						CPrintToChatAll("%t", "Time", RoundFloat(sInterval));
					}
				}
			}
		}
	}
}

public OnSkeletonSpawn(any:ref) {
	new ent = EntRefToEntIndex(ref);
	AcceptEntityInput(gZSent, "kill");
	if(IsValidEntity(ent)) {
		new temp_index = gIndex;
		if(gActiveTimer == false) temp_index = gIndexCmd;
		else {
			if(arg_index == 1) {
				temp_index = gIndex;
				arg_index = 0;
			}
			else {
				if(sMode == 1) temp_index = gIndex == 0 ? GetArraySize(gArray)-1 : gIndex-1;
				else temp_index = gIndex;
			}
		}
		new playerCounter = GetClientCount(true);
		decl String:sName[64], String:sBase[16], String:sScale[16], String:sLifetime[32], String:sModel[256], String:sSize[16], String:sGlow[8];
		new Handle:iTrie = GetArrayCell(gArray, temp_index);
		GetTrieString(iTrie, "Name", sName, sizeof(sName));
		PrintToChatAll("%s", sName);
		GetTrieString(iTrie, "Model", sModel, sizeof(sModel));
		GetTrieString(iTrie, "Base", sBase, sizeof(sBase));
		GetTrieString(iTrie, "Scale", sScale, sizeof(sScale));
		GetTrieString(iTrie, "Lifetime", sLifetime, sizeof(sLifetime));
		GetTrieString(iTrie, "Size", sSize, sizeof(sSize));
		GetTrieString(iTrie, "Glow", sGlow, sizeof(sGlow));
		new BaseHP = StringToInt(sBase);
		new ScaleHP = StringToInt(sScale);
		new sHealth = (BaseHP + ScaleHP*playerCounter)*10;
		SetEntProp(ent, Prop_Data, "m_iHealth", sHealth);
		SetEntProp(ent, Prop_Data, "m_iMaxHealth", sHealth);
		if(!StrEqual(sModel, NULL_STRING)) {
			SetEntityModel(ent, sModel);
		}
		if(gActiveTimer) {
			gBCount++;
			gBoss = ent;
		}
		new Float:iSize = StringToFloat(sSize);
		new iGlow = iGlow = StrEqual(sGlow, "Yes") ? 1 : 0;
		SetSize(iSize, ent);
		SetGlow(iGlow, ent);
		bTimer = CreateTimer(StringToFloat(sLifetime), RemoveTimer);
		CPrintToChatAll("%t", "Boss_Spawn", sName);
		UpdateSkeleton(ent, temp_index);
		gQueue = false;
	}
}

//Taken from SoulSharD
public OnPropSpawn(any:ref) {
	new ent = EntRefToEntIndex(ref);
	if(IsValidEntity(ent)) {
		new parent = GetEntPropEnt(ent, Prop_Data, "m_pParent");
		if(IsValidEntity(parent)) {
			decl String:strClassname[64];
			GetEntityClassname(parent, strClassname, sizeof(strClassname));
			if(StrEqual(strClassname, "headless_hatman", false))
			{
				new temp_index = gIndex;
				if(gActiveTimer == false) temp_index = gIndexCmd;
				else {
					if(sMode == 1) temp_index = gIndex == 0 ? GetArraySize(gArray)-1 : gIndex-1;
					else temp_index = gIndex;
				}
				decl String:sWModel[256];
				new Handle:iTrie = GetArrayCell(gArray, temp_index);
				GetTrieString(iTrie, "WeaponModel", sWModel, sizeof(sWModel));
				if(!StrEqual(sWModel, NULL_STRING)){
					if(StrEqual(sWModel, "Invisible")) {
						SetEntityModel(ent, "");
					}
					else {
						SetEntityModel(ent, sWModel);
						SetEntPropEnt(parent, Prop_Send, "m_hActiveWeapon", ent);
					}
				}
			}
		}
	}
}

UpdateSkeleton(ent, temp_index) {
	if(IsValidEntity(ent)) {
		decl String:sSize[16], String:sGlow[8];
		new Handle:iTrie = GetArrayCell(gArray, temp_index);
		GetTrieString(iTrie, "Size", sSize, sizeof(sSize));
		GetTrieString(iTrie, "Glow", sGlow, sizeof(sGlow));
		SetSize(StringToFloat(sSize), ent);
		SetGlow(StrEqual(sGlow, "Yes") ? 1 : 0, ent);
	}
}  

FindHealthBar() {
	gHPbar = FindEntityByClassname(-1, "monster_resource");
	if(gHPbar == -1) {
		gHPbar = CreateEntityByName("monster_resource");
		if(gHPbar != -1) {
			DispatchSpawn(gHPbar);
		}
	}
}

public Action:OnBossDamaged(victim, &attacker, &inflictor, &Float:damage, &damagetype) {
	UpdateBossHealth(victim);
}

public UpdateBossHealth(ent) {
	if (gHPbar == -1) return;
	new percentage;
	if(IsValidEntity(ent)) {
		new HP = GetEntProp(ent, Prop_Data, "m_iHealth");
		new maxHP = GetEntProp(ent, Prop_Data, "m_iMaxHealth");
		if(HP <= (maxHP * 0.9)) {
			SetEntProp(ent, Prop_Data, "m_iHealth", 0);
			ClearTimer(bTimer);
			if(HP <= -1) {
				SetEntProp(ent, Prop_Data, "m_takedamage", 0);
			}
			percentage = 0;
		}
		else {
			percentage = RoundToCeil((float(HP) / float(maxHP / 10)) * 255.9);	//max 255.9 accurate at 100%
		}
	}
	else {
		percentage = 0;
	}
	SetEntProp(gHPbar, Prop_Send, "m_iBossHealthPercentageByte", percentage);
}

public ClearTimer(&Handle:timer) {  
	if(timer != INVALID_HANDLE) {  
		KillTimer(timer);  
	}  
	timer = INVALID_HANDLE;  
}  
/* ---------------------------------ENTITY MANAGEMENT---------------------------------*/

/* ---------------------------------CONFIG MANAGEMENT---------------------------------*/
public SetupMapConfigs(const String:sFile[]) {
	new String:sPath[PLATFORM_MAX_PATH]; 
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/%s", sFile);
	
	if(!FileExists(sPath)) {
		LogError("[Boss] Error: Can not find map filepath %s", sPath);
		SetFailState("[Boss] Error: Can not find map filepath %s", sPath);
	}
	new Handle:kv = CreateKeyValues("Boss Spawner Map");
	FileToKeyValues(kv, sPath);

	if(!KvGotoFirstSubKey(kv)) {
		LogError("[Boss] Could not read maps file: %s", sPath);
		SetFailState("[Boss] Could not read maps file: %s", sPath);
	}
	
	new mapEnabled = 0;
	new bool:Default = false;
	new tempEnabled = 0;
	new Float:temp_pos[3];
	decl String:requestMap[PLATFORM_MAX_PATH];
	decl String:currentMap[PLATFORM_MAX_PATH];
	decl String:sPosition[64], String:tPosition[64];
	GetCurrentMap(currentMap, sizeof(currentMap));
	do {
		KvGetSectionName(kv, requestMap, sizeof(requestMap));
		if(StrEqual(requestMap, currentMap, false)) {
			mapEnabled = KvGetNum(kv, "Enabled", 0);
			gPos[0] = KvGetFloat(kv, "Position X", 0.0);
			gPos[1] = KvGetFloat(kv, "Position Y", 0.0);
			gPos[2] = KvGetFloat(kv, "Position Z", 0.0);
			KvGetString(kv, "TeleportPosition", sPosition, sizeof(sPosition), NULL_STRING);
			Default = true;
		}
		else if(StrEqual(requestMap, "Default", false)) {
			tempEnabled = KvGetNum(kv, "Enabled", 0);
			temp_pos[0] = KvGetFloat(kv, "Position X", 0.0);
			temp_pos[1] = KvGetFloat(kv, "Position Y", 0.0);
			temp_pos[2] = KvGetFloat(kv, "Position Z", 0.0);
			KvGetString(kv, "TeleportPosition", tPosition, sizeof(tPosition), NULL_STRING);
			
		}
	} while (KvGotoNextKey(kv));
	CloseHandle(kv);
	if(Default == false) {
		mapEnabled = tempEnabled;
		gPos = temp_pos;
		Format(sPosition, sizeof(sPosition), "%s", tPosition);
	}
	decl Float:tpos[3];
	if(!StrEqual(sPosition, NULL_STRING)) {
		new ent;
		while((ent = FindEntityByClassname(ent, "info_target")) != -1) {
			if(IsValidEntity(ent)) {
				decl String:strName[32];
				GetEntPropString(ent, Prop_Data, "m_iName", strName, sizeof(strName));
				if(StrEqual(strName, "spawn_loot")) {
					AcceptEntityInput(ent, "Kill");
				}
				else if(StrEqual(strName, "spawn_loot_blue")) {
					AcceptEntityInput(ent, "kill");
				}
				else if(StrEqual(strName, "spawn_loot_red")) {
					AcceptEntityInput(ent, "kill");
				}
			}
		}
		decl String:sPos[3][16];
		ExplodeString(sPosition, ",", sPos, sizeof(sPos), sizeof(sPos[]));
		tpos[0] = StringToFloat(sPos[0]);
		tpos[1] = StringToFloat(sPos[1]);
		tpos[2] = StringToFloat(sPos[2]);
		PrintToServer("%f %f %f", tpos[0], tpos[1], tpos[2]);
		ent = CreateEntityByName("info_target");
		if(IsValidEntity(ent)) {
			SetEntPropString(ent, Prop_Data, "m_iName", "spawn_loot");
			TeleportEntity(ent, tpos, NULL_VECTOR, NULL_VECTOR);
			DispatchSpawn(ent);
		}
		ent = CreateEntityByName("info_target");
		if(IsValidEntity(ent)) {
			SetEntPropString(ent, Prop_Data, "m_iName", "spawn_loot_blue");
			TeleportEntity(ent, tpos, NULL_VECTOR, NULL_VECTOR);
			DispatchSpawn(ent);
		}
		ent = CreateEntityByName("info_target");
		if(IsValidEntity(ent)) {
			SetEntPropString(ent, Prop_Data, "m_iName", "spawn_loot_red");
			TeleportEntity(ent, tpos, NULL_VECTOR, NULL_VECTOR);
			DispatchSpawn(ent);
		}
	}
	LogMessage("Map: %s, Enabled: %s, Position:%f, %f, %f, TeleportLocation: %f, %f, %f", currentMap, mapEnabled ? "Yes" : "No", gPos[0],gPos[1],gPos[2], tpos[0], tpos[1], tpos[2]);
	if(mapEnabled != 0) {
		gEnabled = true;
		if(GetClientCount(true) >= sMin) {
			HUDTimer();
			CPrintToChatAll("%t", "Time", RoundFloat(sInterval));
		}
	}
	else if(mapEnabled == 0) {
		gEnabled = false;
	}
	LogMessage("Loaded Map configs successfully."); 
}

public SetupBossConfigs(const String:sFile[]) {
	new String:sPath[PLATFORM_MAX_PATH]; 
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/%s", sFile);
	
	if(!FileExists(sPath)) {
		LogError("[Boss] Error: Can not find map filepath %s", sPath);
		SetFailState("[Boss] Error: Can not find map filepath %s", sPath);
	}
	new Handle:kv = CreateKeyValues("Custom Boss Spawner");
	FileToKeyValues(kv, sPath);

	if(!KvGotoFirstSubKey(kv)) {
		LogError("[Boss] Could not read maps file: %s", sPath);
		SetFailState("[Boss] Could not read maps file: %s", sPath);
	}
	
	decl String:sName[64], String:sModel[256], String:sType[32], String:sBase[16], String:sScale[16], String:sWModel[256];
	decl String:sSize[16], String:sGlow[8], String:sPosFix[32], String:sLifetime[32], String:sPosition[32], String:sHorde[8], String:sColor[16];
	decl String:sISound[256], String:sDSound[256];
	do {
		KvGetSectionName(kv, sName, sizeof(sName));
		KvGetString(kv, "Model", sModel, sizeof(sModel), NULL_STRING); //1
		KvGetString(kv, "Type", sType, sizeof(sType));
		KvGetString(kv, "HP Base", sBase, sizeof(sBase), "10000");
		KvGetString(kv, "HP Scale", sScale, sizeof(sScale), "1000");
		KvGetString(kv, "WeaponModel", sWModel, sizeof(sWModel), NULL_STRING);
		KvGetString(kv, "Size", sSize, sizeof(sSize), "1.0");
		KvGetString(kv, "Glow", sGlow, sizeof(sPosFix), "Yes");
		KvGetString(kv, "PosFix", sPosFix, sizeof(sPosFix), "0.0");
		KvGetString(kv, "Lifetime", sLifetime, sizeof(sLifetime), "120");
		KvGetString(kv, "Position", sPosition, sizeof(sPosition), NULL_STRING);
		KvGetString(kv, "Horde", sHorde, sizeof(sHorde), NULL_STRING);
		KvGetString(kv, "Color", sColor, sizeof(sColor), NULL_STRING);
		KvGetString(kv, "IntroSound", sISound, sizeof(sISound), INTRO_SND);
		KvGetString(kv, "DeathSound", sDSound, sizeof(sDSound), DEATH_SND);
		if(!StrEqual(sType, "tf_zombie") && !StrEqual(sHorde, NULL_STRING)) {
			LogError("[Boss] Horde mode only works for Type: tf_zombie.");
			SetFailState("[Boss] Horde mode only works for Type: tf_zombie.");
		}
		if(!StrEqual(sType, "tf_zombie") && !StrEqual(sColor, NULL_STRING)) {
			LogError("[Boss] Color mode only works for Type: tf_zombie.");
			SetFailState("[Boss] Color mode only works for Type: tf_zombie.");
		}
		if(!StrEqual(sType, "headless_hatman") && !StrEqual(sType, "eyeball_boss") && !StrEqual(sType, "merasmus") && !StrEqual(sType, "tf_zombie_spawner") && !StrEqual(sType, "tf_zombie")){
			LogError("[Boss] Type is undetermined, please check boss type again.");
			SetFailState("[Boss] Type is undetermined, please check boss type again.");
		}
		if(StrEqual(sType, "eyeball_boss")) {
			RemoveBossLifeline("tf_eyeball_boss_lifetime", "tf_eyeball_boss_lifetime", StringToInt(sLifetime)+1);
		}
		else if(StrEqual(sType, "merasmus")) {
			RemoveBossLifeline("tf_merasmus_lifetime", "tf_merasmus_lifetime", StringToInt(sLifetime)+1);
		}
		if(!StrEqual(sModel, NULL_STRING)) {
			PrecacheModel(sModel, true);
		}
		if(!StrEqual(sType, "headless_hatman")) {
			if(!StrEqual(sWModel, NULL_STRING)) {
				LogError("[Boss] Weapon model can only be changed on Type:headless_hatman");
				SetFailState("[Boss] Weapon model can only be changed on Type:headless_hatman");
			}
		}
		else if(!StrEqual(sWModel, NULL_STRING)) {
			if(!StrEqual(sWModel, "Invisible")) {
				PrecacheModel(sWModel, true);
			}
		}
		PrecacheSound(sISound);
		PrecacheSound(sDSound);
		new Handle:iTrie = CreateTrie();
		SetTrieString(iTrie, "Name", sName, false);
		SetTrieString(iTrie, "Model", sModel, false);
		SetTrieString(iTrie, "Type", sType, false);
		SetTrieString(iTrie, "Base", sBase, false);
		SetTrieString(iTrie, "Scale", sScale, false);
		SetTrieString(iTrie, "WeaponModel", sWModel, false);
		SetTrieString(iTrie, "Size", sSize, false);
		SetTrieString(iTrie, "Glow", sGlow, false);
		SetTrieString(iTrie, "PosFix", sPosFix, false);
		SetTrieString(iTrie, "Lifetime", sLifetime, false);
		SetTrieString(iTrie, "Position", sPosition, false);
		SetTrieString(iTrie, "Horde", sHorde, false);
		SetTrieString(iTrie, "Color", sColor, false);
		SetTrieString(iTrie, "IntroSound", sISound, false);
		SetTrieString(iTrie, "DeathSound", sDSound, false);
		PushArrayCell(gArray, iTrie);
	} while (KvGotoNextKey(kv));
	CloseHandle(kv);
	LogMessage("Loaded Boss configs successfully."); 
}
/* ---------------------------------CONFIG MANAGEMENT---------------------------------*/

/* ----------------------------------------END----------------------------------------*/