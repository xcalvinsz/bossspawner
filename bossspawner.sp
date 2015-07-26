/*	
 *	============================================================================
 *	
 *	[TF2] Automatic Halloween Boss Spawner
 *	Alliedmodders: http://forums.alliedmods.net/member.php?u=87026
 *	Current Version: 4.0
 *
 *	This plugin is FREE and can be distributed to anyone.  
 *	If you have paid for this plugin, get your money back.
 *	
 *	Version Log:
 *	v.4.0
 *	- Combined and rewritten the hud countdown timer and spawn timers
 *	- Removed a bunch of useless code
 *	- Fixed a bunch of timer errors
 *	- Fixed issue with timer not counting down by 1 interval seconds
 *	- Fixed issue with 2+ bosses spawning the same time
 *	- Fixed issue with plugin not spawning anything at all
 * 	- Fixed min players not working properly and causing to break the plugin
 *	- Fixed issue with cvar changing commands
 *	v.3.0
 * 	- Skeleton King added w/ Health modifier & Size Scale & Glow effect
 * 	- !forceboss <arg> (0 - Horseman, 1 - Monoculus, 2 - Merasmus, 3 - Skeleton King)
 *	- Added a map config to specify the position for each map (sm_reloadbossconfig)
 *	- Added translation files
 *	- Fixed call stack error for horseman removal
 *	- Fixed call stack error for HUD timer when map changes
 *
 *	v.2.0 -  11/1/2013
 *	- Instead of looping through entities to find and kill off, it uses ent references (safer) ***
 *	- Fixed sm_boss_enabled not working properly ***
 *	- Precache missing files ***
 *	- Fixed changing time interval spawn not taking effect immediately ***
 *	- Fixed round restart spawning 2 bosses ***
 *	- Fixed boss sometimes not respawning ***
 *	- Fixed map change spawning 2 bosses ***
 *	- Code cleanup and bug fixes ***
 *	- Added support for tf2 beta ***
 *	- Added slay command (sm_slayboss)***
 *	- Added morecolors to chat ***
 *	- Added horseman auto-remove with cvar (sm_boss_horseman_remove) ***
 *	- Added force boss spawn command (sm_forceboss) ***
 *	- Added HUD time disply for next spawn ***
 *	- Added cvar to specify how many players before spawning (sm_boss_minplayers) ***
 *	- Removed useless codes ***
 *	- Removed IsValidClient checks ***
 *	
 *	1.0 - Released
 *	
 *	Description:
 *	Automatically spawns a rotation of halloween bosses
 *
 *	============================================================================
 */

#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <morecolors>

#define PLUGIN_VERSION "4.0"
#define HEALTHBAR_CLASS "monster_resource"
#define HEALTHBAR_PROPERTY "m_iBossHealthPercentageByte"
#define HEALTHBAR_MAX 255

new Handle:Version = 		INVALID_HANDLE;
new Handle:Mode = 			INVALID_HANDLE;
new Handle:Time = 			INVALID_HANDLE;
new Handle:MinPlayers = 	INVALID_HANDLE;
new Handle:Remove = 		INVALID_HANDLE;
new Handle:TimerHandle = 	INVALID_HANDLE;
new Handle:HorsemanHP = 	INVALID_HANDLE;
new Handle:MonoHP = 		INVALID_HANDLE;
new Handle:MerasHP = 		INVALID_HANDLE;
new Handle:SkeletonHP = 	INVALID_HANDLE;
new Handle:HorsemanScale = 	INVALID_HANDLE;
new Handle:MonoScale = 		INVALID_HANDLE;
new Handle:MerasScale = 	INVALID_HANDLE;
new Handle:SkeletonScale = 	INVALID_HANDLE;
new Handle:Horseman = 		INVALID_HANDLE;
new Handle:Monoculus = 		INVALID_HANDLE;
new Handle:Merasmus = 		INVALID_HANDLE;
new Handle:Skeleton = 		INVALID_HANDLE;
new Handle:BossGlow = 		INVALID_HANDLE;
new Handle:BossSize = 		INVALID_HANDLE;
new Handle:HorsemanTimer = 	INVALID_HANDLE;
new Handle:hudText = 		INVALID_HANDLE;

new g_Time;
new bool:g_Enabled;
new bossEnt = -1;
new SpawnEnt = -1;
new bool:queueBoss = false;
new Float:g_pos[3];
new generator;
new bossCounter;
new g_trackEntity = -1;
new g_healthBar = -1;
new Float:Skeleton_maxHP;
new Float:Skeleton_currentHP;

public Plugin:myinfo =  {
	name = "[TF2] Automatic Halloween Boss Spawner",
	author = "Tak (chaosxk)",
	description = "Spawns a boss under a spawn time interval.",
	version = PLUGIN_VERSION,
	url = "http://www.sourcemod.net"
}

public OnPluginStart() {
	//Adjustable Cvars
	Version = CreateConVar("sm_boss_version", PLUGIN_VERSION, "Halloween Boss Spawner Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	
	Mode = CreateConVar("sm_boss_mode", "1", "What spawn mode should boss spawn? (0 - Random ; 1 - Ordered from HHH - Monoculus - Merasmus");
	Time = CreateConVar("sm_boss_interval", "300", "How many seconds until the next boss spawns?");
	MinPlayers = CreateConVar("sm_boss_minplayers", "12", "How many players are needed before enabling auto-spawning?");
	Remove = CreateConVar("sm_boss_horseman_remove", "210", "How many seconds until the horseman leaves?");

	Horseman = CreateConVar("sm_boss_horseman", "1", "Allow horseman to spawn in rotation?");
	Monoculus = CreateConVar("sm_boss_monoculus", "1", "Allow monoculus to spawn in rotation?");
	Merasmus = CreateConVar("sm_boss_merasmus", "1", "Allow merasmus to spawn in rotation?");
	Skeleton = CreateConVar("sm_boss_skeleton", "1", "Allow skeleton king to  spawn in rotation");

	HorsemanHP = CreateConVar("sm_boss_horsehp", "10000", "Base HP for horseman.");
	MonoHP = CreateConVar("sm_boss_monohp", "10000", "HBase HP for monoculus.");
	MerasHP = CreateConVar("sm_boss_merashp", "10000", "Base HP for merasmus.");
	SkeletonHP = CreateConVar("sm_boss_skeletonhp", "10000", "Base HP for skeleton.");

	HorsemanScale = CreateConVar("sm_boss_horsescale", "200", "How much additional health does horseman gain per player on server.");
	MonoScale = CreateConVar("sm_boss_monoscale", "200", "How much additional health does monoculus gain per player on server.");
	MerasScale = CreateConVar("sm_boss_merasscale", "200", "How much additional health does merasmus gain per player on server.");
	SkeletonScale = CreateConVar("sm_boss_skeletonscale", "200", "How much additional health does skeleton king gain per player on server.");

	BossGlow = CreateConVar("sm_boss_glow", "0", "Should bosses glow through walls?");
	BossSize = CreateConVar("sm_boss_size", "1.0", "Size of boss when they spawn?");

	RegAdminCmd("sm_getcoords", GetCoords, ADMFLAG_GENERIC, "Get the Coordinates of your cursor.");
	RegAdminCmd("sm_forceboss", ForceSpawn, ADMFLAG_GENERIC, "Forces a boss to spawn");
	RegAdminCmd("sm_slayboss", SlayBoss, ADMFLAG_GENERIC, "Forces a boss to die");
	RegAdminCmd("sm_reloadbossconfig", ReloadConfig, ADMFLAG_GENERIC, "Reloads the map setting config");

	//Event Hooks
	HookEvent("teamplay_round_start", RoundStart);

	//Convar Hooks
	HookConVarChange(Version, cvarChange);
	HookConVarChange(Horseman, cvarChange);
	HookConVarChange(Monoculus, cvarChange);
	HookConVarChange(Merasmus, cvarChange);
	HookConVarChange(Skeleton, cvarChange);
	HookConVarChange(BossGlow, cvarChange);
	HookConVarChange(BossSize, cvarChange);
	HookConVarChange(Time, cvarChange);
	HookConVarChange(MinPlayers, cvarChange);
	
	LoadTranslations("common.phrases");
	LoadTranslations("bossspawner.phrases");
	AutoExecConfig(true, "bossspawner");
}

public OnPluginEnd() {
	RemoveExistingBoss();
}

public OnConfigsExecuted() {
	SetupMapConfigs("bossspawner_maps.cfg");
	if(!g_Enabled) return;
	FindHealthBar();
	PrecacheSound("ui/halloween_boss_summoned_fx.wav");
}

public OnMapEnd() {
	RemoveExistingBoss();
	if(!g_Enabled) return;
	ClearTimer(TimerHandle);
}

public OnClientPostAdminCheck(client) {
	if(GetClientCount(true) == GetConVarInt(MinPlayers)) {
		if(bossCounter == 0) {
			ResetTimer();
		}
	}
}

public OnClientDisconnect(client) {
	if(GetClientCount(true) < GetConVarInt(MinPlayers)) {
		RemoveExistingBoss();
		ClearTimer(TimerHandle);
	}
}

public cvarChange(Handle:convar, String:oldValue[], String:newValue[]) {
	if(convar == Version) {
		SetConVarString(Version, newValue, false, false);
	}
	else if((convar == Horseman) || (convar == Monoculus) || (convar == Merasmus) || (convar == Skeleton) || (convar == Time) || (convar == MinPlayers)) {
		if(GetClientCount(true) >= GetConVarInt(MinPlayers)) {
			if(bossCounter == 0) {
				ResetTimer();
			}
		}
		else {
			RemoveExistingBoss();
			ClearTimer(TimerHandle);
		}
	}
	else if(convar == BossGlow) {
		SetGlow(StringToInt(newValue));
	}
	else if(convar == BossSize) {
		SetSize(StringToFloat(newValue));
	}
}

public Action:RoundStart(Handle:event, const String:name[], bool:dontBroadcast) {
	bossCounter = 0;
	if(!g_Enabled) return Plugin_Continue;
	ClearTimer(TimerHandle);
	if(GetClientCount(true) >= GetConVarInt(MinPlayers)) {
		if(bossCounter == 0) {
			ResetTimer();
		}
	}
	return Plugin_Continue;
}

public OnEntityDestroyed(entity) {
	if(g_Enabled) {
		if(IsValidEntity(entity) && entity > MaxClients) {
			decl String:classname[MAX_NAME_LENGTH];
			GetEntityClassname(entity, classname, sizeof(classname));
			if(entity == bossEnt) {
				bossEnt = -1;
				bossCounter--;
				if(bossCounter == 0) {
					CPrintToChatAll("%t", "Time", RoundFloat(GetConVarFloat(Time)));
					hudTimer();
				}
				if(StrEqual(classname, "headless_hatman")) {
					ClearTimer(HorsemanTimer);
				}
			}
			if(entity == g_trackEntity) {
				g_trackEntity = FindEntityByClassname(-1, "merasmus");
				if (g_trackEntity == entity) {
					g_trackEntity = FindEntityByClassname(entity, "merasmus");
				}
					
				if (g_trackEntity > -1) {
					SDKHook(g_trackEntity, SDKHook_OnTakeDamagePost, OnBossDamaged);
				}
				UpdateBossHealth(g_trackEntity);
			}
		}
	}
}

public Action:ForceSpawn(client, args) {
	if(!g_Enabled) return Plugin_Handled;
	new String:arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	if(bossCounter == 0) {
		ClearTimer(TimerHandle);
		if(args == 0) SpawnBoss();
		else {
			new num = StringToInt(arg);
			if(num == 0) spawnHorseman();
			else if(num == 1) spawnMonoculus();
			else if(num == 2) spawnMerasmus();
			else if(num == 3) spawnSkeleton();
		}
	}
	else {
		CReplyToCommand(client, "%t", "Boss_Active");
	}
	return Plugin_Handled;
}

public Action:GetCoords(client, args) {
	if(!g_Enabled) return Plugin_Handled;
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
	if(!g_Enabled) return Plugin_Handled;
	if(IsValidEntity(bossEnt)) {
		decl String:classname[MAX_NAME_LENGTH];
		GetEntityClassname(bossEnt, classname, sizeof(classname));
		if(StrEqual(classname, "headless_hatman")) {
			CPrintToChatAll("%t", "Horseman_Slain");
		}
		else if(StrEqual(classname, "eyeball_boss")) {
			CPrintToChatAll("%t", "Eyeball_Slain");
		}
		else if(StrEqual(classname, "merasmus")) {
			CPrintToChatAll("%t", "Merasmus_Slain");
		}
		else if(StrEqual(classname, "tf_zombie")) {
			CPrintToChatAll("%t", "Skeleton_Slain");
		}
		AcceptEntityInput(bossEnt, "Kill");
	}
	else {
		CReplyToCommand(client, "%t", "No_Boss");
	}
	//OnEntityDestroyed(bossEnt);
	return Plugin_Handled;
}

public Action:ReloadConfig(client, args) {
	ClearTimer(TimerHandle);
	SetupMapConfigs("bossspawner_maps.cfg");
	ReplyToCommand(client, "[Boss Spawner] Boss configs have been reloaded!");
}

//random or ordered spawn manager
SpawnBoss() {
	new mode = GetConVarInt(Mode);
	new bool:horseVal = GetConVarBool(Horseman);
	new bool:monoVal = GetConVarBool(Monoculus);
	new bool:merasVal = GetConVarBool(Merasmus);
	new bool:skelVal = GetConVarBool(Skeleton);
	if(mode == 0) {
		generator = GetRandomInt(0,3);
	}
	while(generator == 0 && !horseVal || generator == 1 && !monoVal || generator == 2 && !merasVal || generator == 3 && !skelVal) {
		switch(mode) {
			case 0: generator = GetRandomInt(0,3);
			case 1: {
				generator++;
				if(generator == 4) {
					generator = 0;
				}
			}
		}
		if(!horseVal && !monoVal && !merasVal && !skelVal) {
			generator = 3;
		}
	}
	switch(generator) {
		case 0: {
			spawnHorseman();
			switch(mode) {
				case 0: generator = 0;
				case 1: generator++;
			}
		}
		case 1: {
			spawnMonoculus();
			switch(mode) {
				case 0: generator = 0;
				case 1: generator++;
			}
		}
		case 2: {
			spawnMerasmus();
			switch(mode) {
				case 0: generator = 0;
				case 1: generator++;
			}
		}
		case 3: {
			spawnSkeleton();
			switch(mode) {
				case 0: generator = 0;
				case 1: generator++;
			}
		}
		case 4: {
			generator = 0;
			SpawnBoss();
		}
	}
}

public Action:RemoveHorseman(Handle:hTimer) {
	if(IsValidEntity(bossEnt)) {
		AcceptEntityInput(bossEnt, "Kill");
		CPrintToChatAll("%t", "Horseman_Left");
	}
	return Plugin_Handled;
}

spawnHorseman() {
	new entity = CreateEntityByName("headless_hatman");
	if(IsValidEntity(entity)) {
		new playerCounter = GetClientCount(true);
		TeleportEntity(entity, g_pos, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(entity);
		SetEntProp(entity, Prop_Data, "m_iHealth", (GetConVarInt(HorsemanHP) + GetConVarInt(HorsemanScale)*playerCounter)*4);
		SetEntProp(entity, Prop_Data, "m_iMaxHealth", (GetConVarInt(HorsemanHP) + GetConVarInt(HorsemanScale)*playerCounter)*4);
		bossCounter++;
		bossEnt = entity;
		SetGlow(GetConVarInt(BossGlow));
		SetSize(GetConVarFloat(BossSize));
		HorsemanTimer = CreateTimer(GetConVarFloat(Remove), RemoveHorseman);
	}
}

spawnMonoculus() {
	new entity = CreateEntityByName("eyeball_boss");
	if(IsValidEntity(entity)) {
		new playerCounter = GetClientCount(true);
		TeleportEntity(entity, g_pos, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(entity);
		SetEntProp(entity, Prop_Data, "m_iTeamNum", 5);
		SetEntProp(entity, Prop_Data, "m_iHealth", GetConVarInt(MonoHP) + GetConVarInt(MonoScale)*playerCounter);
		SetEntProp(entity, Prop_Data, "m_iMaxHealth", GetConVarInt(MonoHP) + GetConVarInt(MonoScale)*playerCounter);
		decl String:targetname[32];
		GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
		bossCounter++;
		bossEnt = entity;
		SetGlow(GetConVarInt(BossGlow));
		SetSize(GetConVarFloat(BossSize));
	}
}

spawnMerasmus() {
	new entity = CreateEntityByName("merasmus");
	if(IsValidEntity(entity)) {
		new playerCounter = GetClientCount(true);
		TeleportEntity(entity, g_pos, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(entity);
		SetEntProp(entity, Prop_Data, "m_iHealth", (GetConVarInt(MerasHP) + GetConVarInt(MerasScale)*playerCounter)*4);
		SetEntProp(entity, Prop_Data, "m_iMaxHealth", (GetConVarInt(MerasHP) + GetConVarInt(MerasScale)*playerCounter)*4);
		bossCounter++;
		bossEnt = entity;
		SetGlow(GetConVarInt(BossGlow));
		SetSize(GetConVarFloat(BossSize));
	}
}

spawnSkeleton() {
	new entity = CreateEntityByName("tf_zombie_spawner");
	if(IsValidEntity(entity)) {
		EmitSoundToAll("ui/halloween_boss_summoned_fx.wav");
		TeleportEntity(entity, g_pos, NULL_VECTOR, NULL_VECTOR);
		SetEntProp(entity, Prop_Data, "m_nSkeletonType", 1);
		SpawnEnt = entity;
		DispatchSpawn(entity);
		bossCounter++;
		queueBoss = true;
		AcceptEntityInput(entity, "Enable");
		new playerCounter = GetClientCount(true);
		Skeleton_maxHP = float((GetConVarInt(SkeletonHP) + GetConVarInt(SkeletonScale)*playerCounter)*4);
		Skeleton_currentHP = Skeleton_maxHP;
	}
}

SetGlow(value) {
	if(IsValidEntity(bossEnt)) {
		SetEntProp(bossEnt, Prop_Send, "m_bGlowEnabled", value);
	}
}

SetSize(Float:value) {
	if(IsValidEntity(bossEnt)) {
		SetEntPropFloat(bossEnt, Prop_Send, "m_flModelScale", value);
	}
}

ResetTimer() {
	if(bossCounter == 0) {
		CPrintToChatAll("%t", "Time", RoundFloat(GetConVarFloat(Time)));
		ClearTimer(TimerHandle);
		hudTimer();
	}
}

public hudTimer() {
	if(!g_Enabled) return;
	g_Time = GetConVarInt(Time);
	if(hudText != INVALID_HANDLE) {
		for(new i = 1; i <= MaxClients; i++) {
			if(IsClientInGame(i))
				ClearSyncHud(i, hudText);
		}
		CloseHandle(hudText);
	}
	hudText = CreateHudSynchronizer();
	SetHudTextParams(0.05, 0.05, 1.0, 255, 255, 255, 255);
	TimerHandle = CreateTimer(1.0, HUDCountDown, _, TIMER_REPEAT);
}
public Action:HUDCountDown(Handle:hTimer) {
	g_Time--;
	for(new i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			ShowSyncHudText(i, hudText, "Boss: %d seconds", g_Time);
		}
	}
	if(g_Time <= 0) {
		SpawnBoss();
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

//remove existing boss that has the same targetname so that it doesn't cause an extra spawn point
RemoveExistingBoss() {
	if(IsValidEntity(bossEnt)) {
		AcceptEntityInput(bossEnt, "kill");
		bossCounter = 0;
	}
}

FindHealthBar() {
	g_healthBar = FindEntityByClassname(-1, HEALTHBAR_CLASS);
	if(g_healthBar == -1) {
		g_healthBar = CreateEntityByName(HEALTHBAR_CLASS);
		if(g_healthBar != -1) {
			DispatchSpawn(g_healthBar);
		}
	}
}

public OnEntityCreated(entity, const String:classname[]) {
	if(StrEqual(classname, HEALTHBAR_CLASS)) {
		g_healthBar = entity;
	}
	else if(g_trackEntity == -1 && (StrEqual(classname, "merasmus") 
	|| StrEqual(classname, "headless_hatman") || StrEqual(classname, "tf_zombie"))) {
		g_trackEntity = entity;
		SDKHook(entity, SDKHook_SpawnPost, UpdateBossHealth);
		SDKHook(entity, SDKHook_OnTakeDamage, OnBossDamaged);
	}
	if(StrEqual(classname, "tf_zombie") && queueBoss == true) {
		bossEnt = entity;
		AcceptEntityInput(SpawnEnt, "kill");
		CPrintToChatAll("%t", "Skeleton_Spawn");
		CreateTimer(0.1, UpdateSkeleton, _);
		queueBoss = false;
	}
}

public Action:UpdateSkeleton(Handle:timer) { 
	SetGlow(GetConVarInt(BossGlow));
	SetSize(GetConVarFloat(BossSize)*2);
}  

public Action:OnBossDamaged(victim, &attacker, &inflictor, &Float:damage, &damagetype) {
	if(IsValidEntity(victim) && (0 < attacker <= MaxClients && IsClientInGame(attacker))) {
		decl String:classname[32]; 
		GetEdictClassname(victim, classname, sizeof(classname)); 
		if(StrEqual(classname, "tf_zombie") && victim == bossEnt) {
			Skeleton_currentHP -= damage;
			UpdateBossHealth(victim);
			UpdateDeathEvent(victim);
			damage = 0.0;
			return Plugin_Changed;
		}
	}
	UpdateBossHealth(victim);
	UpdateDeathEvent(victim);
	return Plugin_Continue;
}

public UpdateDeathEvent(entity) {
	if(IsValidEntity(entity)) {
		new maxHP, HP;
		decl String:classname[32]; 
		GetEdictClassname(entity, classname, sizeof(classname)); 
		if(StrEqual(classname, "tf_zombie") && entity == bossEnt) {
			maxHP = RoundToZero(Skeleton_maxHP);
			HP = RoundToZero(Skeleton_currentHP);
			if(HP <= 0) {
				SetEntProp(entity, Prop_Data, "m_takedamage", 9999);
				return;
			}
		}
		else {
			maxHP = GetEntProp(entity, Prop_Data, "m_iMaxHealth");
			HP = GetEntProp(entity, Prop_Data, "m_iHealth");
		}
		if(HP <= (maxHP * 0.75)) {
			SetEntProp(entity, Prop_Data, "m_iHealth", 0);
			if(HP <= -1) {
				SetEntProp(entity, Prop_Data, "m_takedamage", 0);
			}
		}
	}
}

public UpdateBossHealth(entity) {
	if(g_healthBar == -1) {
		return;
	}
	new percentage;
	if(IsValidEntity(entity)) {
		new maxHP, HP;
		decl String:classname[32]; 
		GetEdictClassname(entity, classname, sizeof(classname)); 
		if(StrEqual(classname, "tf_zombie") && entity == bossEnt) {
			maxHP = RoundToZero(Skeleton_maxHP);
			HP = RoundToZero(Skeleton_currentHP);
		}
		else {
			maxHP = GetEntProp(entity, Prop_Data, "m_iMaxHealth");
			HP = GetEntProp(entity, Prop_Data, "m_iHealth");
		}
		if(HP <= 0) {
			percentage = 0;
		}
		else {
			percentage = RoundToCeil((float(HP) / float(maxHP / 4)) * HEALTHBAR_MAX);
		}
	}
	else {
		percentage = 0;
	}	
	SetEntProp(g_healthBar, Prop_Send, HEALTHBAR_PROPERTY, percentage);
}

public ClearTimer(&Handle:timer) {  
	if(timer != INVALID_HANDLE) {  
		KillTimer(timer);  
	}  
	timer = INVALID_HANDLE;  
}  

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
			g_pos[0] = KvGetFloat(kv, "Position X", 0.0);
			g_pos[1] = KvGetFloat(kv, "Position Y", 0.0);
			g_pos[2] = KvGetFloat(kv, "Position Z", 0.0);
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
		g_pos = temp_pos;
	}
	LogMessage("Map: %s, Enabled: %s, Position:%f, %f, %f", currentMap, mapEnabled ? "Yes" : "No", g_pos[0],g_pos[1],g_pos[2]);
	if(mapEnabled != 0) {
		g_Enabled = true;
		if(GetClientCount(true) >= GetConVarInt(MinPlayers)) {
			CPrintToChatAll("%t", "Time", RoundFloat(GetConVarFloat(Time)));
			hudTimer();
		}
	}
	else if(mapEnabled == 0) {
		g_Enabled = false;
	}
	LogMessage("Loaded Map configs successfully."); 
}