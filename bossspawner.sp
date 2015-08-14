/*	
 *	============================================================================
 *	
 *	[TF2] Custom Boss Spawner
 *	Alliedmodders: http://forums.alliedmods.net/member.php?u=87026
 *	Current Version: 4.1
 *
 *	This plugin is FREE and can be distributed to anyone.  
 *	If you have paid for this plugin, get your money back.
 *	
 *	Version Log:
 *	v.4.2
 *	- Now uses tries/hashmaps instead of multi-arrays
 *	- Fixed call stack error onclientdisconnect timer
 * 	- Fixed issue with !spawn <boss> not spawning at users' cursor
 *	- Adds native(to do)
 *	============================================================================
 */
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <morecolors>

#define PLUGIN_VERSION "4.2"

new Handle:cVars[6] = 	{INVALID_HANDLE, ...};
new Handle:cTimer = 	INVALID_HANDLE;
new Handle:bTimer = 	INVALID_HANDLE;
new Handle:hHUD = 		INVALID_HANDLE;
new Handle:gArray = 	INVALID_HANDLE;

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
new bool:gRands;
new gBCount = 0;
new gTrack = -1;
new gHPbar = -1;
new gBSpawn;
new gIndexCmd;

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
	HookEvent("pumpkin_lord_summoned", Horse_Summoned, EventHookMode_Pre);
	HookEvent("pumpkin_lord_killed", Horse_Killed, EventHookMode_Pre);
	HookEvent("merasmus_summoned", Merasmus_Summoned, EventHookMode_Pre);
	HookEvent("merasmus_killed", Merasmus_Killed, EventHookMode_Pre);
	HookEvent("eyeball_boss_summoned", Monoculus_Summoned, EventHookMode_Pre);
	HookEvent("eyeball_boss_killed", Monoculus_Killed, EventHookMode_Pre);
	HookEvent("merasmus_escape_warning", Merasmus_Leave, EventHookMode_Pre);
	HookEvent("eyeball_boss_escape_imminent", Monoculus_Leave, EventHookMode_Pre);

	HookConVarChange(cVars[0], cVarChange);
	HookConVarChange(cVars[1], cVarChange);
	HookConVarChange(cVars[2], cVarChange);
	HookConVarChange(cVars[3], cVarChange);
	HookConVarChange(cVars[4], cVarChange);
	HookConVarChange(cVars[5], cVarChange);
	
	gArray = CreateArray();
	
	LoadTranslations("common.phrases");
	LoadTranslations("bossspawner.phrases");
	AutoExecConfig(true, "bossspawner");
}

public OnPluginEnd() {
	RemoveExistingBoss();
	ClearTimer(cTimer);
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
		PrecacheSound("ui/halloween_boss_summoned_fx.wav");
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

public Action:Horse_Summoned(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!gEnabled) return Plugin_Continue;
	EmitSoundToAll("ui/halloween_boss_summoned_fx.wav");
	return Plugin_Handled;
}

public Action:Horse_Killed(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!gEnabled) return Plugin_Continue;
	EmitSoundToAll("ui/halloween_boss_defeated_fx.wav");
	return Plugin_Handled;
}

public Action:Merasmus_Summoned(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!gEnabled) return Plugin_Continue;
	EmitSoundToAll("ui/halloween_boss_summoned_fx.wav");
	return Plugin_Handled;
}

public Action:Merasmus_Killed(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!gEnabled) return Plugin_Continue;
	EmitSoundToAll("ui/halloween_boss_defeated_fx.wav");
	return Plugin_Handled;
}

public Action:Monoculus_Summoned(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!gEnabled) return Plugin_Continue;
	EmitSoundToAll("ui/halloween_boss_summoned_fx.wav");
	return Plugin_Handled;
}

public Action:Monoculus_Killed(Handle:event, const String:name[], bool:dontBroadcast) {
	if(!gEnabled) return Plugin_Continue;
	EmitSoundToAll("ui/halloween_boss_defeated_fx.wav");
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
	if(gBCount != 0) {
		CReplyToCommand(client, "%t", "Boss_Active");
		return Plugin_Handled;
	}
	new String:arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	if(gBCount == 0) {
		ClearTimer(cTimer);
		SpawnBoss();
	}
	else {
		CReplyToCommand(client, "%t", "Boss_Active");
	}
	return Plugin_Handled;
}

public Action:GetCoords(client, args) {
	if(!gEnabled) return Plugin_Handled;
	if(!IsClientInGame(client) || !IsPlayerAlive(client)) {
		ReplyToCommand(client, "%t", "Error");
		return Plugin_Handled;
	}
	new Float:l_pos[3];
	GetClientAbsOrigin(client, l_pos);
	ReplyToCommand(client, "[Boss Spawner] Coords: %0.0f,%0.0f,%0.0f\n[Boss Spawner] Use those coordinates and place them in configs/bossspawner_maps.cfg", l_pos[0], l_pos[1], l_pos[2]);
	return Plugin_Handled;
}

public Action:SlayBoss(client, args) {
	if(!gEnabled) {
		ReplyToCommand(client, "[Boss] Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
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
	CPrintToChatAll("%t", "Boss_Slain");
	return Plugin_Handled;
}

public Action:ReloadConfig(client, args) {
	ClearTimer(cTimer);
	SetupMapConfigs("bossspawner_maps.cfg");
	SetupMapConfigs("bossspawner_boss.cfg");
	ReplyToCommand(client, "[Boss Spawner] Configs have been reloaded!");
}

public Action:SpawnBossCommand(client, args) {
	if(!gEnabled) return Plugin_Handled;
	if(!IsClientInGame(client) || !IsPlayerAlive(client)) {
		ReplyToCommand(client, "%t", "Error");
		return Plugin_Handled;
	}
	if(!SetTeleportEndPoint(client)) {
		ReplyToCommand(client, "[Boss] Could not find spawn point.");
		return Plugin_Handled;
	}
	if(args != 1) {
		ReplyToCommand(client, "[Boss] Format: sm_spawn <boss>");
		return Plugin_Handled;
	}
	kPos[2] -= 10.0;
	decl String:arg[15];
	GetCmdArg(1, arg, sizeof(arg));
	new i;
	new Handle:iTrie = INVALID_HANDLE;
	decl String:sName[64];
	for(i = 0; i < GetArraySize(gArray); i++) {
		iTrie = GetArrayCell(gArray, i);
		if(iTrie != INVALID_HANDLE) {
			GetTrieString(iTrie, "Name", sName, sizeof(sName));
			if(StrEqual(sName, arg, false)){
				break;
			}
		}
	}
	if(i == GetArraySize(gArray)) {
		ReplyToCommand(client, "[Boss] Error: Boss does not exist.");
		return Plugin_Handled;
	}
	gIndexCmd = i;
	gActiveTimer = false;
	CreateBoss(gIndexCmd, kPos, true);
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
public SpawnBoss() {
	gActiveTimer = true;
	if(sMode == 0) {
		gRands = true;
		gIndex = GetRandomInt(0, GetArraySize(gArray)-1);
		CreateBoss(gIndex, gPos, false);
	}
	else if(sMode == 1) {
		gRands = false;
		CreateBoss(gIndex, gPos, false);
		gIndex++;
		if(gIndex > GetArraySize(gArray)-1) gIndex = 0;
	}
}

public CreateBoss(b_index, Float:kpos[3], bool:cmd) {
	new Float:temp[3];
	temp[0] = kpos[0];
	temp[1] = kpos[1];
	temp[2] = kpos[2];

	decl String:sName[64], String:sModel[256], String:sType[32], String:sBase[16], String:sScale[16];
	decl String:sSize[16], String:sGlow[8], String:sPosFix[32], String:sLifetime[32], String:sPosition[32];
	new Handle:iTrie = GetArrayCell(gArray, b_index);
	GetTrieString(iTrie, "Name", sName, sizeof(sName));
	GetTrieString(iTrie, "Model", sModel, sizeof(sModel));
	GetTrieString(iTrie, "Type", sType, sizeof(sType));
	GetTrieString(iTrie, "Base", sBase, sizeof(sBase));
	GetTrieString(iTrie, "Scale", sScale, sizeof(sScale));
	GetTrieString(iTrie, "Size", sSize, sizeof(sSize));
	GetTrieString(iTrie, "Glow", sGlow, sizeof(sGlow));
	GetTrieString(iTrie, "PosFix", sPosFix, sizeof(sPosFix));
	GetTrieString(iTrie, "Lifetime", sLifetime, sizeof(sLifetime));
	GetTrieString(iTrie, "Position", sPosition, sizeof(sPosition));
	if(!StrEqual(sPosition, NULL_STRING) && !cmd) {
		decl String:sPos[3][16];
		ExplodeString(sPosition, ",", sPos, sizeof(sPos), sizeof(sPos[]));
		temp[0] = StringToFloat(sPos[0]);
		temp[1] = StringToFloat(sPos[1]);
		temp[2] = StringToFloat(sPos[2]);
	}
	new ent = CreateEntityByName(sType);
	if(IsValidEntity(ent)) {
		if(StrEqual(sType, "tf_zombie_spawner")) {
			SetEntProp(ent, Prop_Data, "m_nSkeletonType", 1);
			temp[2] += StringToFloat(sPosFix);
			TeleportEntity(ent, temp, NULL_VECTOR, NULL_VECTOR);
			DispatchSpawn(ent);
			EmitSoundToAll("ui/halloween_boss_summoned_fx.wav");
			gBSpawn = ent;
			gQueue = true;
			AcceptEntityInput(ent, "Enable");
			return;
		}
		new playerCounter = GetClientCount(true);
		new BaseHP = StringToInt(sBase);
		new ScaleHP = StringToInt(sScale);
		new sHealth = (BaseHP + ScaleHP*playerCounter)*10;
		if(StrEqual(sType, "eyeball_boss")) SetEntProp(ent, Prop_Data, "m_iTeamNum", 5);
		temp[2] += StringToFloat(sPosFix);
		TeleportEntity(ent, temp, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(ent);
		SetEntProp(ent, Prop_Data, "m_iHealth", sHealth);
		SetEntProp(ent, Prop_Data, "m_iMaxHealth", sHealth);
		EmitSoundToAll("ui/halloween_boss_summoned_fx.wav");
		if(!StrEqual(sModel, NULL_STRING)) {
			SetEntityModel(ent, sModel);
		}
		if(gActiveTimer == true) {
			gBCount = 1;
			gBoss = ent;
			bTimer = CreateTimer(StringToFloat(sLifetime), RemoveTimer, b_index);
		}
		CPrintToChatAll("%t", "Boss_Spawn", sName);
		SetSize(StringToFloat(sSize), ent);
		SetGlow(StrEqual(sGlow, "Yes") ? 1 : 0, ent);
	}
}

public Action:RemoveTimer(Handle:hTimer, any:b_index) {
	if(IsValidEntity(gBoss)) {
		decl String:sName[64];
		new Handle:iTrie = GetArrayCell(gArray, b_index);
		GetTrieString(iTrie, "Name", sName, sizeof(sName));
		CPrintToChatAll("%t", "Boss_Left", sName);
		CPrintToChatAll("[Boss] %s has left due to boredom.", sName);
		AcceptEntityInput(gBoss, "Kill");
		gBCount = 0;
	}
	return Plugin_Handled;
}

RemoveExistingBoss() {
	if(IsValidEntity(gBoss)) {
		AcceptEntityInput(gBoss, "kill");
		gBCount = 0;
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
		SpawnBoss();
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
	if(StrEqual(classname, "tf_zombie") && gQueue == true) {
		gTrack = ent;
		RequestFrame(OnSkeletonSpawn, EntIndexToEntRef(ent));
		SDKHook(ent, SDKHook_SpawnPost, UpdateBossHealth);
		SDKHook(ent, SDKHook_OnTakeDamagePost, OnBossDamaged);
	}
	if(StrEqual(classname, "prop_dynamic")) {
		RequestFrame(OnPropSpawn, EntIndexToEntRef(ent));
	}
}

public OnEntityDestroyed(ent) {
	if(gEnabled) {
		if(IsValidEntity(ent) && ent > MaxClients) {
			decl String:classname[MAX_NAME_LENGTH];
			GetEntityClassname(ent, classname, sizeof(classname));
			if(ent == gBoss) {
				gBoss = -1;
				gBCount = 0;
				if(gBCount == 0) {
					HUDTimer();
					CPrintToChatAll("%t", "Time", RoundFloat(sInterval));
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
		}
	}
}

public OnSkeletonSpawn(any:ref) {
	new ent = EntRefToEntIndex(ref);
	if(IsValidEntity(ent)) {
		new temp_index = gIndex;
		if(gActiveTimer == false) temp_index = gIndexCmd;
		else {
			if(gRands == false) temp_index = gIndex == 0 ? GetArraySize(gArray)-1 : gIndex-1;
			else temp_index = gIndex;
		}
		new playerCounter = GetClientCount(true);
		decl String:sName[64], String:sBase[16], String:sScale[16], String:sLifetime[32];
		new Handle:iTrie = GetArrayCell(gArray, temp_index);
		GetTrieString(iTrie, "Name", sName, sizeof(sName));
		GetTrieString(iTrie, "Base", sBase, sizeof(sBase));
		GetTrieString(iTrie, "Scale", sScale, sizeof(sScale));
		GetTrieString(iTrie, "Lifetime", sLifetime, sizeof(sLifetime));
		new BaseHP = StringToInt(sBase);
		new ScaleHP = StringToInt(sScale);
		new sHealth = (BaseHP + ScaleHP*playerCounter)*10;
		SetEntProp(ent, Prop_Data, "m_iHealth", sHealth);
		SetEntProp(ent, Prop_Data, "m_iMaxHealth", sHealth);
		if(gActiveTimer) {
			gBCount = 1;
			gBoss = ent;
		}
		AcceptEntityInput(gBSpawn, "kill");
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
					if(gRands == false) temp_index = gIndex == 0 ? GetArraySize(gArray)-1 : gIndex-1;
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
		LogError("[Boss Spawner] Error: Can not find map filepath %s", sPath);
		SetFailState("[Boss Spawner] Error: Can not find map filepath %s", sPath);
	}
	new Handle:kv = CreateKeyValues("Boss Spawner Map");
	FileToKeyValues(kv, sPath);

	if(!KvGotoFirstSubKey(kv)) SetFailState("Could not read maps file: %s", sPath);
	
	new mapEnabled = 0;
	new bool:Default = false;
	new tempEnabled = 0;
	new Float:temp_pos[3];
	decl String:requestMap[PLATFORM_MAX_PATH];
	decl String:currentMap[PLATFORM_MAX_PATH];
	GetCurrentMap(currentMap, sizeof(currentMap));
	do {
		KvGetSectionName(kv, requestMap, sizeof(requestMap));
		if(StrEqual(requestMap, currentMap, false)) {
			mapEnabled = KvGetNum(kv, "Enabled", 0);
			gPos[0] = KvGetFloat(kv, "Position X", 0.0);
			gPos[1] = KvGetFloat(kv, "Position Y", 0.0);
			gPos[2] = KvGetFloat(kv, "Position Z", 0.0);
			Default = true;
		}
		else if(StrEqual(requestMap, "Default", false)) {
			tempEnabled = KvGetNum(kv, "Enabled", 0);
			temp_pos[0] = KvGetFloat(kv, "Position X", 0.0);
			temp_pos[1] = KvGetFloat(kv, "Position Y", 0.0);
			temp_pos[2] = KvGetFloat(kv, "Position Z", 0.0);
		}
	} while (KvGotoNextKey(kv));
	CloseHandle(kv);
	if(Default == false) {
		mapEnabled = tempEnabled;
		gPos = temp_pos;
	}
	LogMessage("Map: %s, Enabled: %s, Position:%f, %f, %f", currentMap, mapEnabled ? "Yes" : "No", gPos[0],gPos[1],gPos[2]);
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
		LogError("[Boss Spawner] Error: Can not find map filepath %s", sPath);
		SetFailState("[Boss Spawner] Error: Can not find map filepath %s", sPath);
	}
	new Handle:kv = CreateKeyValues("Custom Boss Spawner");
	FileToKeyValues(kv, sPath);

	if(!KvGotoFirstSubKey(kv)) SetFailState("Could not read maps file: %s", sPath);
	
	decl String:sName[64], String:sModel[256], String:sType[32], String:sBase[16], String:sScale[16], String:sWModel[256];
	decl String:sSize[16], String:sGlow[8], String:sPosFix[32], String:sLifetime[32], String:sPosition[32];
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
		if(StrEqual(sType, "tf_zombie_spawner") && !StrEqual(sModel, NULL_STRING)) {
			LogError("Skeleton type is not supported.");
			SetFailState("Skeleton type is not supported.");
		}
		if(!StrEqual(sType, "headless_hatman") && !StrEqual(sType, "eyeball_boss") && !StrEqual(sType, "merasmus") && !StrEqual(sType, "tf_zombie_spawner")){
			LogError("Type is undetermined, please check boss type again.");
			SetFailState("Type is undetermined, please check boss type again.");
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
				LogError("Weapon model can only be changed on Type:headless_hatman");
				SetFailState("Weapon model can only be changed on Type:headless_hatman");
			}
		}
		else if(!StrEqual(sWModel, NULL_STRING)) {
			if(!StrEqual(sWModel, "Invisible")) {
				PrecacheModel(sWModel, true);
			}
		}
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
		PushArrayCell(gArray, iTrie);
	} while (KvGotoNextKey(kv));
	CloseHandle(kv);
	LogMessage("Loaded Boss configs successfully."); 
}
/* ---------------------------------CONFIG MANAGEMENT---------------------------------*/

/* ----------------------------------------END----------------------------------------*/