/*	
 *	============================================================================
 *	
 *	[TF2] Custom Boss Spawner
 *	Alliedmodders: https://forums.alliedmods.net/showthread.php?t=218119
 *	Current Version: 4.4.1
 *
 *	Written by Tak (Chaosxk)
 *	https://forums.alliedmods.net/member.php?u=87026
 *
 *	This plugin is FREE and can be distributed to anyone.  
 *	If you have paid for this plugin, get your money back.
 *	
Version Log:
v.4.4.1 -
	Fixed a bug where bosses that die normally then trying to use the command !fb would say boss is already spawned
	Fixed a bug where manual spawned bosses would get killed on on player disconnecting
	Bosses will no longer get force removed by plugin when players disconnect below the treshold: sm_boss_minplayers (only timers will stop)
	Fixed sm_boss_minplayer if statements not working properly due to improper int/float comparison
	Changed OnClientDisconnect to OnClientDisconenct_Post to fix client count which was off by 1
	SDKUnhook on client disconnect post
v.4.4  -
Added -
	Added Cvar:sm_healthbar_type to change healthbar display type: 0-off 1-hudbar 2-hudtext 3-both
Changes -
	Changed the way data is stored, now uses arraylists and datapacks instead of saving in entity itself
	Changed more code into object-oriented
	Changed !sb and !spawnboss, can now be used while spectating (Note: Boss will spawn directly on player that you are spectating)
	Changes !slayboss command will now only reply back to player and not to all players
Removed -
	Removed command:sm_reloadbossconfig, just reload plugin which is better to do
	Blocks the message "player has killed horseman/merasmus/monoculus" when boss dies
Fixes -
	Fixed a bug when slaying a boss then spawning another would say the boss is still active
	Fixed a bug where all info_target entities were getting removed by this plugin causing some map functions to break
	Fixed a big where console would say spawn_boss_alt not found: was a typo and changed to spawn_loot_alt
	Fixed a bug where DeathSound key would not play properly on multiple boss spawns: now uses datapacks as references
	Fixed a bug where healthbar would not work properly on multiple bosses
	Improved healthbar carry over to another boss when one of them dies
	Fixed a bug where healthbar would show negative values when dying
	Fixed a bug where health/scale/size/glow was not working properly even though it was defined in .cfg file
	Fixed a bug with players disconnecting would cause auto-spawned bosses to break
	Fixed a bug with hitbox not scaling properly (Note: Some models do not scale 1:1 with the hitboxes)
	Fixed a memory leak on data timers
Others -
	Fixed some small typos in code
	Cleaned up useless comments
	
	
Known Issues:
	- When tf_skeleton with a hat attacks you while standing still, his hat model may freeze until he starts moving
	- eyeball_boss can die from collision from a payload cart, most of time in air so it doesn't matter too much
	- Hat size and offset does not change if player manually spawns a boss with a different size from the config (e.g !horseman 1000 5 1 : Horseman size is 5 but default size in boss config is 1, if this boss has a hat the hat won't resize)
 *	============================================================================
 */
#pragma semicolon 1
#include <morecolors>
#include <sdktools>
#pragma newdecls required
#include <sourcemod>
#include <sdkhooks>

#define PLUGIN_VERSION "4.4.1"
#define INTRO_SND	"ui/halloween_boss_summoned_fx.wav"
#define DEATH_SND	"ui/halloween_boss_defeated_fx.wav"
#define HORSEMAN	"headless_hatman"
#define MONOCULUS	"eyeball_boss"
#define MERASMUS	"merasmus"
#define SKELETON	"tf_zombie"
#define SNULL 		""

ConVar cVars[7] = {null, ...};
Handle cTimer = null;
ArrayList gArray = null;
ArrayList gData = null;

//Variables for ConVars conversion
int sMode, sHealthBar, sMin;
float sInterval, sHUDx, sHUDy;
bool gEnabled;

//Other variables
int gIndex, gIndexCmd;
float gPos[3], kPos[3];
bool gActiveTimer;
int g_AutoBoss, gTrack = -1, gHPbar = -1;

//Index saving
int argIndex, saveIndex;

public Plugin myinfo =  {
	name = "[TF2] Custom Boss Spawner",
	author = "Tak (chaosxk)",
	description = "An advanced custom boss spawner.",
	version = PLUGIN_VERSION,
	url = "http://www.sourcemod.net"
}

public void OnPluginStart() {
	cVars[0] = CreateConVar("sm_boss_version", 		PLUGIN_VERSION, "Custom Boss Spawner Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	cVars[1] = CreateConVar("sm_boss_mode", 		"1", 			"Spawn mode for auto-spawning [0:Random | 1:Ordered]");
	cVars[2] = CreateConVar("sm_boss_interval", 	"300", 			"How many seconds until the next boss spawns?");
	cVars[3] = CreateConVar("sm_boss_minplayers", 	"12", 			"How many players are needed before enabling auto-spawning?");
	cVars[4] = CreateConVar("sm_boss_hud_x", 		"0.05", 		"X-Coordinate of the HUD display.");
	cVars[5] = CreateConVar("sm_boss_hud_y", 		"0.05", 		"Y-Coordinate of the HUD display");
	cVars[6] = CreateConVar("sm_healthbar_type", 	"3", 			"What kind of healthbar to display? [0:None | 1:HUDBar | 2:HUDText | 3:Both]");

	RegAdminCmd("sm_getcoords", 		GetCoords, 		ADMFLAG_GENERIC, "Get the Coordinates of your cursor.");
	RegAdminCmd("sm_forceboss", 		ForceBoss, 		ADMFLAG_GENERIC, "Forces a auto-spawning boss to spawn early.");
	RegAdminCmd("sm_fb", 				ForceBoss, 		ADMFLAG_GENERIC, "Forces a auto-spawning boss to spawn early.");
	RegAdminCmd("sm_spawnboss", 		SpawnMenu, 		ADMFLAG_GENERIC, "Opens a menu to spawn a boss.");
	RegAdminCmd("sm_sb", 				SpawnMenu, 		ADMFLAG_GENERIC, "Opens a menu to spawn a boss.");
	RegAdminCmd("sm_slayboss", 			SlayBoss, 		ADMFLAG_GENERIC, "Slay all active bosses on map.");
	
	HookEvent("teamplay_round_start", 			RoundStart);
	HookEvent("pumpkin_lord_summoned", 			Boss_Summoned, 		EventHookMode_Pre);
	HookEvent("pumpkin_lord_killed", 			Boss_Killed, 		EventHookMode_Pre);
	HookEvent("merasmus_summoned", 				Boss_Summoned, 		EventHookMode_Pre);
	HookEvent("merasmus_killed", 				Boss_Killed, 		EventHookMode_Pre);
	HookEvent("eyeball_boss_summoned", 			Boss_Summoned, 		EventHookMode_Pre);
	HookEvent("eyeball_boss_killed", 			Boss_Killed, 		EventHookMode_Pre);
	HookEvent("merasmus_escape_warning", 		Merasmus_Leave, 	EventHookMode_Pre);
	HookEvent("eyeball_boss_escape_imminent", 	Monoculus_Leave, 	EventHookMode_Pre);
	
	HookUserMessage(GetUserMessageId("SayText2"), SayText2, true);

	for(int i = 0; i < 7; i++)
		cVars[i].AddChangeHook(cVarChange);
	
	gArray = new ArrayList();
	gData = new ArrayList();
	CreateTimer(0.5, HealthTimer, _);

	LoadTranslations("common.phrases");
	LoadTranslations("bossspawner.phrases");
	AutoExecConfig(true, "bossspawner");
}

public void OnPluginEnd() {
	ClearTimer(cTimer);
	RemoveExistingBoss();
	//reset flags for cheat cmds lifetime
	int flags = GetCommandFlags("tf_eyeball_boss_lifetime");
	SetCommandFlags("tf_eyeball_boss_lifetime", flags|FCVAR_CHEAT);
	flags = GetCommandFlags("tf_merasmus_lifetime");
	SetCommandFlags("tf_merasmus_lifetime", flags|FCVAR_CHEAT);
}

public void OnConfigsExecuted() {
	sMode 		= 	GetConVarInt(cVars[1]);
	sInterval 	= 	GetConVarFloat(cVars[2]);
	sMin		= 	GetConVarInt(cVars[3]);
	sHUDx 		= 	GetConVarFloat(cVars[4]);
	sHUDy 		= 	GetConVarFloat(cVars[5]);
	sHealthBar 	= 	GetConVarInt(cVars[6]);
	SetupMapConfigs("bossspawner_maps.cfg");
	SetupBossConfigs("bossspawner_boss.cfg");
	SetupDownloads("bossspawner_downloads.cfg");
	if(gEnabled) {
		FindHealthBar();
		PrecacheSound("items/cart_explode.wav");
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientInGame(i)) {
				SDKHook(i, SDKHook_OnTakeDamage, OnClientDamaged);
			}
		}
	}
}

public void RemoveBossLifeline(const char[] command, const char[] execute, int duration) {
	int flags = GetCommandFlags(command); 
	SetCommandFlags(command, flags & ~FCVAR_CHEAT); 
	ServerCommand("%s %d", execute, duration);
	//SetCommandFlags(command, flags|FCVAR_CHEAT); 
}

public void OnMapEnd() {
	ClearTimer(cTimer);
	RemoveExistingBoss();
}

public void OnClientPostAdminCheck(int client) {
	if(GetClientCount(true) == sMin) {
		if(g_AutoBoss == 0) {
			ResetTimer();
		}
	}
	SDKHook(client, SDKHook_OnTakeDamage, OnClientDamaged);
}

public void OnClientDisconnect_Post(int client) {
	if(GetClientCount(true) < sMin) {
		ClearTimer(cTimer);
		//RemoveExistingBoss();
	}
	SDKUnhook(client, SDKHook_OnTakeDamage, OnClientDamaged);
}

public void cVarChange(Handle convar, char[] oldValue, char[] newValue) {
	if (StrEqual(oldValue, newValue, true))
		return;
	
	float iNewValue = StringToFloat(newValue);

	if(convar == cVars[0])  {
		SetConVarString(cVars[0], PLUGIN_VERSION);
	}
	else if(convar == cVars[1]) {
		sMode = RoundFloat(iNewValue);
	}
	else if((convar == cVars[2]) || (convar == cVars[3])) {
		if(convar == cVars[2]) sInterval = iNewValue;
		else sMin = RoundFloat(iNewValue);
		
		if(GetClientCount(true) >= sMin) {
			if(g_AutoBoss == 0) {
				ResetTimer();
			}
		}
		else {
			ClearTimer(cTimer);
			//RemoveExistingBoss();
		}
	}
	else if(convar == cVars[4]) {
		sHUDx = iNewValue;
	}
	else if(convar == cVars[5]) {
		sHUDy = iNewValue;
	}
	else if(convar == cVars[6]) {
		sHealthBar = RoundFloat(iNewValue);
	}
}

public Action SayText2(UserMsg msg_id, Handle bf, int[] players, int playersNum, bool reliable, bool init) {
	if(!reliable) 
		return Plugin_Continue;
	
	char buffer[128];
	BfReadByte(bf);
	BfReadByte(bf);
	
	BfReadString(bf, buffer, sizeof(buffer));
	
	if(StrEqual(buffer, "#TF_Halloween_Boss_Killers")) {
		return Plugin_Handled;
	}
	if(StrEqual(buffer, "#TF_Halloween_Eyeball_Boss_Killers")) {
		return Plugin_Handled;
	}
	if(StrEqual(buffer, "#TF_Halloween_Merasmus_Killers")) {
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

/* -----------------------------------EVENT HANDLES-----------------------------------*/
public Action RoundStart(Handle event, const char[] name, bool dontBroadcast) {
	g_AutoBoss = 0;
	if(!gEnabled) return Plugin_Continue;
	ClearTimer(cTimer);
	if(GetClientCount(true) >= sMin) {
		if(g_AutoBoss == 0) {
			ResetTimer();
		}
	}
	return Plugin_Continue;
}

public Action Boss_Summoned(Handle event, const char[] name, bool dontBroadcast) {
	if(!gEnabled) return Plugin_Continue;
	return Plugin_Handled;
}

public Action Boss_Killed(Handle event, const char[] name, bool dontBroadcast) {
	if(!gEnabled) return Plugin_Continue;
	return Plugin_Handled;
}

public Action Merasmus_Leave(Handle event, const char[] name, bool dontBroadcast) {
	if(!gEnabled) return Plugin_Continue;
	return Plugin_Handled;
}

public Action Monoculus_Leave(Handle event, const char[] name, bool dontBroadcast) {
	if(!gEnabled) return Plugin_Continue;
	return Plugin_Handled;
}
/* -----------------------------------EVENT HANDLES-----------------------------------*/

/* ---------------------------------COMMAND FUNCTION----------------------------------*/

public Action ForceBoss(int client, int args) {
	if(!gEnabled) {
		CReplyToCommand(client, "{frozen}[Boss] {orange}Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
	if(g_AutoBoss == 0) {
		gActiveTimer = true;
		if(args == 1) {
			saveIndex = gIndex;
			char arg1[32];
			char sName[64];
			GetCmdArg(1, arg1, sizeof(arg1));
			int i;
			for(i = 0; i < gArray.Length; i++) {
				StringMap HashMap = gArray.Get(i);
				HashMap.GetString("Name", sName, sizeof(sName));
				if(StrEqual(sName, arg1, false)) {
					gIndex = i;
					break;
				}
			}
			if(i == gArray.Length) {
				CReplyToCommand(client, "{frozen}[Boss] {red}Error: {orange}Boss does not exist.");
				return Plugin_Handled;
			}
			ClearTimer(cTimer);
			argIndex = 1;
			CreateBoss(gIndex, gPos, -1, -1, -1.0, -1, false);
		}
		else if(args == 0) {
			argIndex = 0;
			ClearTimer(cTimer);
			SpawnBoss(-1,-1.0,-1);
		}
		else {
			CReplyToCommand(client, "{frozen}[Boss] {red}Format: {orange}!forceboss <bossname>");
		}
	}
	else {
		CReplyToCommand(client, "%t", "Boss_Active");
	}
	return Plugin_Handled;
}

public Action GetCoords(int client, int args) {
	if(!gEnabled) {
		CReplyToCommand(client, "{frozen}[Boss] {orange}Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
	if(!IsClientInGame(client) || !IsPlayerAlive(client)) {
		CReplyToCommand(client, "{frozen}[Boss] You must be alive and in-game to use this command.");
		return Plugin_Handled;
	}
	float l_pos[3];
	GetClientAbsOrigin(client, l_pos);
	CReplyToCommand(client, "{frozen}[Boss] {orange}Coordinates: %0.0f,%0.0f,%0.0f\n{frozen}[Boss] {orange}Use those coordinates and place them in configs/bossspawner_maps.cfg", l_pos[0], l_pos[1], l_pos[2]);
	return Plugin_Handled;
}

public Action SlayBoss(int client, int args) {
	if(!gEnabled) {
		CReplyToCommand(client, "{frozen}[Boss] {orange}Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
	ClearTimer(cTimer);
	RemoveExistingBoss();
	CReplyToCommand(client, "%t", "Boss_Slain");
	return Plugin_Handled;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs) {
	char arg[4][64];
	int args = ExplodeString(sArgs, " ", arg, sizeof(arg), sizeof(arg[]));
	//int returnType = 0;
	if(arg[0][0] == '!' || arg[0][0] == '/') {
		strcopy(arg[0], 64, arg[0][1]);
	}
	else return Plugin_Continue;
	int i;
	StringMap HashMap = null;
	char sName[64];
	for(i = 0; i < gArray.Length; i++) {
		HashMap = gArray.Get(i);
		HashMap.GetString("Name", sName, sizeof(sName));
		if(StrEqual(sName, arg[0], false)){
			break;
		}
	}
	if(i == gArray.Length) {
		return Plugin_Continue;
	}
	if(!gEnabled) {
		CPrintToChat(client, "{frozen}[Boss] {orange}Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
	if(!CheckCommandAccess(client, "sm_boss_override", ADMFLAG_GENERIC, false)) {
		CPrintToChat(client, "{frozen}[Boss] {orange}You do not have access to this command.");
		return Plugin_Handled;
	}
	if(!IsClientInGame(client) || !IsPlayerAlive(client)) {
		CPrintToChat(client, "{frozen}[Boss] {orange}You must be alive and in-game to use this command.");
		return Plugin_Handled;
	}
	if(!SetTeleportEndPoint(client)) {
		CPrintToChat(client, "{Frozen}[Boss] {orange}Could not find spawn point.");
		return Plugin_Handled;
	}
	kPos[2] -= 10.0;
	int iBaseHP = -1, iScaleHP = -1, iGlow = -1;
	float iSize = -1.0;
	if(args > 1) {
		iBaseHP = StringToInt(arg[1]);
		iScaleHP = 0;
	}
	if(args > 2) {
		iSize = StringToFloat(arg[2]);
	}
	if(args > 3) {
		iGlow = StringToInt(arg[3]);
	}
	gIndexCmd = i;
	gActiveTimer = false;
	CreateBoss(gIndexCmd, kPos, iBaseHP, iScaleHP, iSize, iGlow, true);
	return Plugin_Handled;
}

public Action SpawnBossCommand(int client, const char[] command, int args) {
	char arg1[64], arg2[32], arg3[32];
	GetCmdArg(1, arg1, sizeof(arg1));
	int i;
	StringMap HashMap = null;
	char sName[64];
	int nIndex = FindCharInString(command, '_', _) + 1;
	char command2[64];
	strcopy(command2, sizeof(command2), command[nIndex]);
	for(i = 0; i < gArray.Length; i++) {
		HashMap = gArray.Get(i);
		HashMap.GetString("Name", sName, sizeof(sName));
		if(StrEqual(sName, command2, false)){
			break;
		}
	}
	if(i == gArray.Length) {
		return Plugin_Continue;
	}
	if(!gEnabled) {
		CPrintToChat(client, "{frozen}[Boss] {orange}Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
	if(!CheckCommandAccess(client, "sm_boss_override", ADMFLAG_GENERIC, false)) {
		CPrintToChat(client, "{frozen}[Boss] {orange}You do not have access to this command.");
		return Plugin_Handled;
	}
	if(!IsClientInGame(client) || !IsPlayerAlive(client)) {
		CPrintToChat(client, "{frozen}[Boss] {orange}You must be alive and in-game to use this command.");
		return Plugin_Handled;
	}
	if(!SetTeleportEndPoint(client)) {
		CPrintToChat(client, "{Frozen}[Boss] {orange}Could not find spawn point.");
		return Plugin_Handled;
	}
	kPos[2] -= 10.0;
	int iBaseHP = -1, iScaleHP = -1, iGlow = -1;
	float iSize = -1.0;
	if(args > 0) {
		GetCmdArg(1, arg1, sizeof(arg1));
		iBaseHP = StringToInt(arg1);
		iScaleHP = 0;
	}
	if(args > 1) {
		GetCmdArg(2, arg2, sizeof(arg2));
		iSize = StringToFloat(arg2);
	}
	if(args > 2) {
		GetCmdArg(3, arg3, sizeof(arg3));
		iGlow = StringToInt(arg3);
	}
	gIndexCmd = i;
	gActiveTimer = false;
	CreateBoss(gIndexCmd, kPos, iBaseHP, iScaleHP, iSize, iGlow, true);
	return Plugin_Handled;
}

public Action SpawnMenu(int client, int args) {
	if(!gEnabled) {
		CReplyToCommand(client, "{frozen}[Boss] {orange}Custom Boss Spawner is disabled.");
		return Plugin_Handled;
	}
	if(!IsClientInGame(client)) {
		CReplyToCommand(client, "{frozen}[Boss] You must be alive and in-game to use this command.");
		return Plugin_Handled;
	}
	ShowMenu(client);
	return Plugin_Handled;
}

public void ShowMenu(int client) {
	StringMap HashMap = null;
	char sName[64], sInfo[8];
	Menu menu = new Menu(DisplayHealth);
	SetMenuTitle(menu, "Boss Menu");
	for(int i = 0; i < gArray.Length; i++) {
		HashMap = gArray.Get(i);
		HashMap.GetString("Name", sName, sizeof(sName));
		IntToString(i, sInfo, sizeof(sInfo));
		menu.AddItem(sInfo, sName);
	}
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int DisplayHealth(Menu MenuHandle, MenuAction action, int client, int num) {
	if(action == MenuAction_Select) {
		char info[32];
		MenuHandle.GetItem(num, info, sizeof(info));
		Menu menu = new Menu(DisplaySizes);
		menu.SetTitle("Boss Health");
		char param[32];
		char health[][] = {"1000", "5000", "10000", "15000", "20000", "30000", "50000"};
		for(int i = 0; i < sizeof(health); i++) {
			Format(param, sizeof(param), "%s %s", info, health[i]);
			menu.AddItem(param, health[i]);
		}
		SetMenuExitButton(menu, true);
		menu.ExitButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	else if(action == MenuAction_End) {
		delete MenuHandle;
	}
}

public int DisplaySizes(Menu MenuHandle, MenuAction action, int client, int num) {
	if(action == MenuAction_Select) {
		char info[32];
		MenuHandle.GetItem(num, info, sizeof(info));
		Menu menu = new Menu(DisplayGlow);
		menu.SetTitle("Boss Size");
		char param[32];
		char size[][] = {"0.5", "1.0", "1.5", "2.0", "3.0", "4.0", "5.0"};
		for(int i = 0; i < sizeof(size); i++) {
			Format(param, sizeof(param), "%s %s", info, size[i]);
			menu.AddItem(param, size[i]);
		}
		SetMenuExitButton(menu, true);
		menu.ExitButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	else if(action == MenuAction_End) {
		delete MenuHandle;
	}
}

public int DisplayGlow(Menu MenuHandle, MenuAction action, int client, int num) {
	if(action == MenuAction_Select) {
		char info[32];
		MenuHandle.GetItem(num, info, sizeof(info));
		Menu menu = new Menu(EndMenu);
		menu.SetTitle("Boss Glow");
		char param[32];
		Format(param, sizeof(param), "%s 1", info);
		menu.AddItem(param, "On");
		Format(param, sizeof(param), "%s 0", info);
		menu.AddItem(param, "Off");
		menu.ExitButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	else if(action == MenuAction_End) {
		delete MenuHandle;
	}
}

public int EndMenu(Menu MenuHandle, MenuAction action, int client, int num) {
	if(action == MenuAction_Select) {
		char info[32];
		MenuHandle.GetItem(num, info, sizeof(info));
		char sAttribute[4][16];
		ExplodeString(info, " ", sAttribute, sizeof(sAttribute), sizeof(sAttribute[]));
		int iIndex, iBaseHP, iGlow;
		float iSize;
		iIndex = StringToInt(sAttribute[0]);
		iBaseHP = StringToInt(sAttribute[1]);
		iSize = StringToFloat(sAttribute[2]);
		iGlow = StringToInt(sAttribute[3]);
		if(!SetTeleportEndPoint(client)) {
			CReplyToCommand(client, "{Frozen}[Boss] {orange}Could not find spawn point.");
			return;
		}
		kPos[2] -= 10.0;
		gActiveTimer = false;
		CreateBoss(iIndex, kPos, iBaseHP, 0, iSize, iGlow, true);
	}
	else if(action == MenuAction_End) {
		delete MenuHandle;
	}
}

bool SetTeleportEndPoint(int client) {
	float vAngles[3], vOrigin[3], vBuffer[3], vStart[3], Distance;

	GetClientEyePosition(client,vOrigin);
	GetClientEyeAngles(client, vAngles);

	Handle trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceentFilterPlayer);

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
		delete trace;
		return false;
	}

	delete trace;
	return true;
}

public bool TraceentFilterPlayer(int ent, int contentsMask) {
	return ent > GetMaxClients() || !ent;
}
/* ---------------------------------COMMAND FUNCTION----------------------------------*/

/* --------------------------------BOSS SPAWNING CORE---------------------------------*/
void SpawnBoss(int iBaseHP, float iSize, int iGlow) {
	int iScaleHP = -1;
	if(iBaseHP != -1) {
		iScaleHP = 0;
	}
	gActiveTimer = true;
	if(sMode == 0) {
		gIndex = GetRandomInt(0, gArray.Length-1);
		CreateBoss(gIndex, gPos, iBaseHP, iScaleHP, iSize, iGlow, false);
	}
	else if(sMode == 1) {
		CreateBoss(gIndex, gPos, iBaseHP, iScaleHP, iSize, iGlow, false);
	}
}

public void CreateBoss(int index, float kpos[3], int iBaseHP, int iScaleHP, float iSize, int iGlow, bool isCMD) {
	float temp[3];
	for(int i = 0; i < 3; i++)
		temp[i] = kpos[i];
	
	char sName[64], sModel[256], sType[32], sBase[16], sScale[16], sSize[16], sGlow[8], sPosFix[32];
	char sLifetime[32], sPosition[32], sHorde[8], sColor[16], sHModel[256], sISound[256], sHatPosFix[32], sHatSize[16];

	StringMap HashMap = gArray.Get(index);
	HashMap.GetString("Name", sName, sizeof(sName));
	HashMap.GetString("Model", sModel, sizeof(sModel));
	HashMap.GetString("Type", sType, sizeof(sType));
	HashMap.GetString("Base", sBase, sizeof(sBase));
	HashMap.GetString("Scale", sScale, sizeof(sScale));
	HashMap.GetString("Size", sSize, sizeof(sSize));
	HashMap.GetString("Glow", sGlow, sizeof(sGlow));
	HashMap.GetString("PosFix", sPosFix, sizeof(sPosFix));
	HashMap.GetString("Lifetime", sLifetime, sizeof(sLifetime));
	HashMap.GetString("Position", sPosition, sizeof(sPosition));
	HashMap.GetString("Horde", sHorde, sizeof(sHorde));
	HashMap.GetString("Color", sColor, sizeof(sColor));
	HashMap.GetString("HatModel", sHModel, sizeof(sHModel));
	HashMap.GetString("IntroSound", sISound, sizeof(sISound));
	HashMap.GetString("HatPosFix", sHatPosFix, sizeof(sHatPosFix));
	HashMap.GetString("HatSize", sHatSize, sizeof(sHatSize));
	
	if(iBaseHP == -1) {
		iBaseHP = StringToInt(sBase);
	}
	if(iScaleHP == -1) {
		iScaleHP = StringToInt(sScale);
	}
	if(iSize == -1.0) {
		iSize = StringToFloat(sSize);
	}
	if(iGlow == -1) {
		iGlow = StrEqual(sGlow, "Yes") ? 1 : 0;
	}
	if(strlen(sPosition) != 0 && !isCMD) {
		char sPos[3][16];
		ExplodeString(sPosition, ",", sPos, sizeof(sPos), sizeof(sPos[]));
		for(int i = 0; i < 3; i++)
			temp[i] = StringToFloat(sPos[i]);
	}
	temp[2] += StringToFloat(sPosFix);
	int iMax = StringToInt(sHorde) <= 1 ? 1 : StringToInt(sHorde);
	int playerCounter = GetClientCount(true);
	int sHealth = (iBaseHP + iScaleHP*playerCounter)*(iMax != 1 ? 1 : 10);
	DataPack dMax = new DataPack();
	dMax.WriteCell(iMax);
	for(int i = 0; i < iMax; i++) {
		int ent = CreateEntityByName(sType);
		ArrayList dReference = new ArrayList();
		dReference.Push(dMax);
		dReference.Push(EntIndexToEntRef(ent));
		dReference.Push(index);
		dReference.Push(gActiveTimer);
		gData.Push(dReference);
		
		TeleportEntity(ent, temp, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(ent);
		
		SetSize(iSize, ent);
		SetGlow(iGlow, ent);
		
		SetEntProp		(ent, Prop_Data, "m_iHealth", 		sHealth);
		SetEntProp		(ent, Prop_Data, "m_iMaxHealth", 	sHealth); 
		SetEntProp		(ent, Prop_Data, "m_iTeamNum", 		0);
		SetEntProp		(ent, Prop_Data, "m_iTeamNum", 		StrEqual(sType, MONOCULUS) ? 5 : 0);
		//speed don't work! -.-
		//SetEntPropFloat	(ent, Prop_Data, "m_flSpeed", 	0.0);
		
		if(strlen(sColor) != 0) {
			if(StrEqual(sColor, "Red", false)) SetEntProp(ent, Prop_Send, "m_nSkin", 0);
			else if(StrEqual(sColor, "Blue", false)) SetEntProp(ent, Prop_Send, "m_nSkin", 1);
			else if(StrEqual(sColor, "Green", false)) SetEntProp(ent, Prop_Send, "m_nSkin", 2);
			else if(StrEqual(sColor, "Yellow", false)) SetEntProp(ent, Prop_Send, "m_nSkin", 3);
			else if(StrEqual(sColor, "Random", false)) SetEntProp(ent, Prop_Send, "m_nSkin", GetRandomInt(0, 3));
		}
		if(strlen(sModel) != 0) {
			SetEntityModel(ent, sModel);
		}
		
		if(gActiveTimer) 
			g_AutoBoss++;
			
		if(i == 0) {
			DataPack hPack;
			CreateDataTimer(1.0, RemoveTimerPrint, hPack, TIMER_REPEAT);
			hPack.WriteCell(EntIndexToEntRef(ent));
			hPack.WriteCell(StringToFloat(sLifetime));
			hPack.WriteCell(index);
		}
		DataPack jPack;
		CreateDataTimer(1.0, RemoveTimer, jPack, TIMER_REPEAT);
		jPack.WriteCell(EntIndexToEntRef(ent));
		jPack.WriteCell(StringToFloat(sLifetime));
		if(strlen(sHModel) != 0) {
			int hat = CreateEntityByName("prop_dynamic_override");
			DispatchKeyValue(hat, "model", sHModel);
			DispatchKeyValue(hat, "spawnflags", "256");
			DispatchKeyValue(hat, "solid", "0");
			SetEntPropEnt(hat, Prop_Send, "m_hOwnerEntity", ent);
			//Hacky tacky way..
			//SetEntPropFloat(hat, Prop_Send, "m_flModelScale", iSize > 5 ? (iSize > 10 ? (iSize/5+0.80) : (iSize/4+0.75)) : (iSize/3+0.66));
			SetEntPropFloat(hat, Prop_Send, "m_flModelScale", StringToFloat(sHatSize));
			//SetEntPropFloat(hat, Prop_Send, "m_flModelScale", iSize*StringToFloat(sHatSize));
			DispatchSpawn(hat);	
			
			SetVariantString("!activator");
			AcceptEntityInput(hat, "SetParent", ent, ent, 0);
			
			//maintain the offset of hat to the center of head
			if(!StrEqual(sType, MONOCULUS)) {
				SetVariantString("head");
				AcceptEntityInput(hat, "SetParentAttachment", ent, ent, 0);
				SetVariantString("head");
				AcceptEntityInput(hat, "SetParentAttachmentMaintainOffset", ent, ent, 0);
			}
			float hatpos[3];
			hatpos[2] += StringToFloat(sHatPosFix);//*iSize; //-9.5*iSize
			//hatpos[0] += -5.0;
			TeleportEntity(hat, hatpos, NULL_VECTOR, NULL_VECTOR);
		}
	}
	
	if(!StrEqual(sISound, "none", false)) {
		EmitSoundToAll(sISound, _, _, _, _, 1.0);
	}
	ReplaceString(sName, sizeof(sName), "_", " ");
	CPrintToChatAll("%t", "Boss_Spawn", sName);
	
	if(argIndex == 1) {
		gIndex = saveIndex;
	}
	
	if(gActiveTimer == true) {
		gIndex++;
		if(gIndex > gArray.Length-1) gIndex = 0;
	}
}

public Action RemoveTimer(Handle hTimer, DataPack jPack) {
	jPack.Reset();
	int ent = EntRefToEntIndex(jPack.ReadCell());
	if(IsValidEntity(ent)) {
		float tcounter = jPack.ReadCell();
		if(tcounter <= 0.0) {
			AcceptEntityInput(ent, "Kill");
			return Plugin_Stop;
		}
		else {
			tcounter -= 1.0;
			jPack.Reset();
			jPack.ReadCell();
			jPack.WriteCell(tcounter);
			return Plugin_Continue;
		}
	}
	return Plugin_Stop;
}

public Action RemoveTimerPrint(Handle hTimer, DataPack hPack) {
	hPack.Reset();
	int ent = EntRefToEntIndex(hPack.ReadCell());
	if(IsValidEntity(ent)) {
		float tcounter = hPack.ReadCell();
		if(tcounter <= 0.0) {
			int index = hPack.ReadCell();
			char sName[64];
			StringMap HashMap = gArray.Get(index);
			HashMap.GetString("Name", sName, sizeof(sName));
			CPrintToChatAll("%t", "Boss_Left", sName);
			return Plugin_Stop;
		}
		else {
			tcounter -= 1.0;
			hPack.Reset();
			hPack.ReadCell();
			hPack.WriteCell(tcounter);
			return Plugin_Continue;
		}
	}
	return Plugin_Stop;
}

//Instead of hooking to sdkhook_takedamage, we use a 0.5 timer because of hud overloading when taking damage
public Action HealthTimer(Handle hTimer, any ref) {
	if(sHealthBar == 0 || sHealthBar == 1) {
		CreateTimer(0.5, HealthTimer, _);
		return Plugin_Continue;
	}
	if(gTrack != -1 && IsValidEntity(gTrack)) {
		int HP = GetEntProp(gTrack, Prop_Data, "m_iHealth");
		int maxHP = GetEntProp(gTrack, Prop_Data, "m_iMaxHealth");
		int currentHP = RoundFloat(HP - maxHP * 0.9);
		if(currentHP > maxHP*0.1*0.65) SetHudTextParams(0.46, 0.12, 0.5, 0, 255, 0, 255);
		else if(maxHP*0.1*0.25 < currentHP < maxHP*0.1*0.65) SetHudTextParams(0.46, 0.12, 0.5, 255, 255, 0, 255);
		else SetHudTextParams(0.46, 0.12, 0.5, 255, 0, 0, 255);
		if(currentHP < 0) currentHP = 0;
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientInGame(i)) {
				ShowHudText(i, -1, "HP: %d", currentHP);
			}
		}
	}
	CreateTimer(0.5, HealthTimer, _);
	return Plugin_Continue;
}

void RemoveExistingBoss() {
	int ent = -1;
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

void SetGlow(int value, int ent) {
	if(IsValidEntity(ent)) {
		SetEntProp(ent, Prop_Send, "m_bGlowEnabled", value);
	}
}

void SetSize(float value, int ent) {
	if(IsValidEntity(ent)) {
		ResizeHitbox(ent, value);
		SetEntPropFloat(ent, Prop_Send, "m_flModelScale", value);
	}
}

void ResizeHitbox(int entity, float fScale) {
	float vecBossMin[3], vecBossMax[3];
	GetEntPropVector(entity, Prop_Send, "m_vecMins", vecBossMin);
	GetEntPropVector(entity, Prop_Send, "m_vecMaxs", vecBossMax);
	
	float vecScaledBossMin[3], vecScaledBossMax[3];
	
	vecScaledBossMin = vecBossMin;
	vecScaledBossMax = vecBossMax;
	
	ScaleVector(vecScaledBossMin, fScale);
	ScaleVector(vecScaledBossMax, fScale);
	
	SetEntPropVector(entity, Prop_Send, "m_vecMins", vecScaledBossMin);
	SetEntPropVector(entity, Prop_Send, "m_vecMaxs", vecScaledBossMax);
}
/* --------------------------------BOSS SPAWNING CORE---------------------------------*/

/* ---------------------------------TIMER & HUD CORE----------------------------------*/
public void HUDTimer() {
	if(!gEnabled) return;
	sInterval = GetConVarFloat(cVars[2]);
	cTimer = CreateTimer(1.0, HUDCountDown, _, TIMER_REPEAT);
}

public Action HUDCountDown(Handle hTimer) {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			SetHudTextParams(sHUDx, sHUDy, 1.0, 255, 255, 255, 255);
			ShowHudText(i, -1, "Boss: %d seconds", RoundFloat(sInterval));
		}
	}
	if(sInterval <= 0) {
		SpawnBoss(-1,-1.0,-1);
		cTimer = null;
		return Plugin_Stop;
	}
	sInterval--;
	return Plugin_Continue;
}

void ResetTimer() {
	CPrintToChatAll("%t", "Time", RoundFloat(sInterval));
	ClearTimer(cTimer);
	HUDTimer();
}
/* ---------------------------------TIMER & HUD CORE----------------------------------*/

/* ---------------------------------ENTITY MANAGEMENT---------------------------------*/
public void OnEntityCreated(int ent, const char[] classname) {
	if(!gEnabled) return;
	if(StrEqual(classname, "monster_resource")) {
		gHPbar = ent;
	}
	else if((StrEqual(classname, HORSEMAN) || StrEqual(classname, MONOCULUS) 
	|| StrEqual(classname, MERASMUS) || StrEqual(classname, SKELETON))) {
		/* Too lazy to work on this
		if(StrEqual(classname, SKELETON)) {
			for(int i = 1; i <= MaxClients; i++) {
				if(!IsClientInGame(i) || !IsPlayerAlive(i)) continue;
				float btemp[3], itemp[3];
				GetEntPropVector(ent, Prop_Send, "m_vecOrigin", btemp);
				GetClientAbsOrigin(i, itemp);
				float Distance = GetVectorDistance(btemp, itemp);
				if(Distance <= 5000) {
					int flags = GetCommandFlags("shake"); 
					SetCommandFlags("shake", flags & ~FCVAR_CHEAT);
					FakeClientCommand(i, "shake");	
					SetCommandFlags("shake", flags | FCVAR_CHEAT);
				}
			}			
		}*/
		gTrack = ent;
		SDKHook(ent, SDKHook_OnTakeDamagePost, OnBossDamaged);
		RequestFrame(UpdateBossHealth, EntRefToEntIndex(ent));
	}
	else if(StrEqual(classname, "prop_dynamic")) {
		RequestFrame(OnPropSpawn, EntIndexToEntRef(ent));
	}
}

public void OnEntityDestroyed(int ent) {
	if(!gEnabled) return;
	if(!IsValidEntity(ent)) return;
	if(ent == gTrack) {
		gTrack = FindEntityByClassname(-1, HORSEMAN);
		if(gTrack == ent) {
			gTrack = FindEntityByClassname(ent, HORSEMAN);
		}
		if(gTrack == -1) {
			gTrack = FindEntityByClassname(-1, MONOCULUS);
			if(gTrack == ent) {
				gTrack = FindEntityByClassname(ent, MONOCULUS);
			}
		}
		if(gTrack == -1) {
			gTrack = FindEntityByClassname(-1, MERASMUS);
			if (gTrack == ent) {
				gTrack = FindEntityByClassname(ent, MERASMUS);
			}
		}
		if(gTrack == -1) {
			gTrack = FindEntityByClassname(-1, SKELETON);
			if (gTrack == ent) {
				gTrack = FindEntityByClassname(ent, SKELETON);
			}
		}
		if(gTrack != -1) {
			SDKHook(gTrack, SDKHook_OnTakeDamagePost, OnBossDamaged);
		}
		RequestFrame(UpdateBossHealth, EntRefToEntIndex(gTrack));
	}
	for(int i = gData.Length-1; i >= 0; i--) {
		ArrayList dReference = gData.Get(i);
		int dEnt = EntRefToEntIndex(dReference.Get(1));
		if(ent == dEnt) {
			DataPack dMax = dReference.Get(0);
			dMax.Reset();
			int iMax = dMax.ReadCell();
			int index = dReference.Get(2);
			int timed = dReference.Get(3);
			iMax -= 1;
			dMax.Reset();
			dMax.WriteCell(iMax);
			dReference.Set(0, dMax);
			gData.Erase(i);
			if(iMax == 0) {
				StringMap HashMap = gArray.Get(index);
				char sDSound[256];
				HashMap.GetString("DeathSound", sDSound, sizeof(sDSound));
				if(!StrEqual(sDSound, "none", false)) {
					EmitSoundToAll(sDSound, _, _, _, _, 1.0);
				}
				if(timed && GetClientCount(true) >= sMin) {
					HUDTimer();
					CPrintToChatAll("%t", "Time", RoundFloat(sInterval));
				}
				delete dMax;
			}
			if(timed) {
				g_AutoBoss--;
			}
			delete dReference;
			break;
		}
	}
}

public void OnPropSpawn(any ref) {
	int ent = EntRefToEntIndex(ref);
	if(!IsValidEntity(ent)) return;
	int parent = GetEntPropEnt(ent, Prop_Data, "m_pParent");
	if(!IsValidEntity(parent)) return;
	char strClassname[64];
	GetEntityClassname(parent, strClassname, sizeof(strClassname));
	if(StrEqual(strClassname, HORSEMAN, false)) {
		for(int i = gData.Length-1; i >= 0; i--) {
			ArrayList dReference = gData.Get(i);
			int dEnt = EntRefToEntIndex(dReference.Get(1));
			int dIndex = dReference.Get(2);
			if(parent == dEnt) {
				char sWModel[256];
				StringMap HashMap = gArray.Get(dIndex);
				HashMap.GetString("WeaponModel", sWModel, sizeof(sWModel));
				if(strlen(sWModel) != 0) {
					if(StrEqual(sWModel, "Invisible")) {
						SetEntityModel(ent, "");
					}
					else {
						SetEntityModel(ent, sWModel);
						SetEntPropEnt(parent, Prop_Send, "m_hActiveWeapon", ent);
					}
				}
				break;
			}
		}
	}
}

void FindHealthBar() {
	gHPbar = FindEntityByClassname(-1, "monster_resource");
	if(gHPbar == -1) {
		gHPbar = CreateEntityByName("monster_resource");
		if(gHPbar != -1) {
			DispatchSpawn(gHPbar);
		}
	}
}

public Action OnBossDamaged(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
	UpdateBossHealth(EntRefToEntIndex(victim));
}

public Action OnClientDamaged(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
	if(!IsClientInGame(victim)) return Plugin_Continue;
	if(!IsValidEntity(attacker)) return Plugin_Continue;
	char classname[32];
	GetEntityClassname(attacker, classname, sizeof(classname));
	if(StrEqual(classname, HORSEMAN) || StrEqual(classname, MONOCULUS) || StrEqual(classname, MERASMUS) || StrEqual(classname, SKELETON)) {
		char sDamage[32];
		for(int i = gData.Length-1; i >= 0; i--) {
			ArrayList dReference = gData.Get(i);
			int dEnt = EntRefToEntIndex(dReference.Get(1));
			int dIndex = dReference.Get(2);
			if(attacker == dEnt) {
				StringMap HashMap = gArray.Get(dIndex);
				HashMap.GetString("Damage", sDamage, sizeof(sDamage));
				damage = StringToFloat(sDamage);
				return Plugin_Changed;
			}
		}
	}
	return Plugin_Continue;
}

public void UpdateBossHealth(int ref) {
	if(gHPbar == -1 || sHealthBar == 0 || sHealthBar == 2) {
		return;
	}
	int percentage;
	int ent = EntRefToEntIndex(ref);
	if(IsValidEntity(ent)) {
		int HP = GetEntProp(ent, Prop_Data, "m_iHealth");
		int maxHP = GetEntProp(ent, Prop_Data, "m_iMaxHealth");
		int currentHP = RoundFloat(HP - maxHP * 0.9);
		if(currentHP <= 0) {
			percentage = 0;
			char classname[32];
			GetEntityClassname(ent, classname, sizeof(classname));
			if(StrEqual(classname, SKELETON)) {
				for(int i = gData.Length-1; i >= 0; i--) {
					ArrayList dReference = gData.Get(i);
					int dEnt = EntRefToEntIndex(dReference.Get(1));
					if(ent == dEnt) {
						int dIndex = dReference.Get(2);
						char sGnome[8];
						StringMap HashMap = gArray.Get(dIndex);
						HashMap.GetString("Gnome", sGnome, sizeof(sGnome));
						if(StringToInt(sGnome) == 0) {
							AcceptEntityInput(ent, "kill");
						}
						break;
					}
				}
			}
			else {
				SetEntProp(ent, Prop_Data, "m_iHealth", 0);
			
				if(HP <= -1) {
					SetEntProp(ent, Prop_Data, "m_takedamage", 0);
				}
			}
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

public void ClearTimer(Handle &timer) {  
	if(timer != null) {  
		KillTimer(timer);  
	}  
	timer = null;  
}  
/* ---------------------------------ENTITY MANAGEMENT---------------------------------*/

/* ---------------------------------CONFIG MANAGEMENT---------------------------------*/
public void SetupMapConfigs(const char[] sFile) {
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/%s", sFile);
	
	if(!FileExists(sPath)) {
		LogError("[Boss] Error: Can not find map filepath %s", sPath);
		SetFailState("[Boss] Error: Can not find map filepath %s", sPath);
	}
	KeyValues kv = CreateKeyValues("Boss Spawner Map");
	FileToKeyValues(kv, sPath);

	if(!KvGotoFirstSubKey(kv)) {
		LogError("[Boss] Could not read maps file: %s", sPath);
		SetFailState("[Boss] Could not read maps file: %s", sPath);
	}
	
	int mapEnabled = 0;
	bool Default = false;
	int tempEnabled = 0;
	float temp_pos[3];
	char requestMap[64], currentMap[64], sPosition[64], tPosition[64];
	GetCurrentMap(currentMap, sizeof(currentMap));
	do {
		kv.GetSectionName(requestMap, sizeof(requestMap));
		if(StrEqual(requestMap, currentMap, false)) {
			mapEnabled = kv.GetNum("Enabled", 0);
			gPos[0] = kv.GetFloat("Position X", 0.0);
			gPos[1] = kv.GetFloat("Position Y", 0.0);
			gPos[2] = kv.GetFloat("Position Z", 0.0);
			kv.GetString("TeleportPosition", sPosition, sizeof(sPosition), SNULL);
			Default = true;
		}
		else if(StrEqual(requestMap, "Default", false)) {
			tempEnabled = kv.GetNum("Enabled", 0);
			temp_pos[0] = kv.GetFloat("Position X", 0.0);
			temp_pos[1] = kv.GetFloat("Position Y", 0.0);
			temp_pos[2] = kv.GetFloat("Position Z", 0.0);
			kv.GetString("TeleportPosition", tPosition, sizeof(tPosition), SNULL);
		}
	} while kv.GotoNextKey();
	delete kv;
	if(Default == false) {
		mapEnabled = tempEnabled;
		gPos = temp_pos;
		Format(sPosition, sizeof(sPosition), "%s", tPosition);
	}
	float tpos[3];
	if(strlen(sPosition) != 0) {
		int ent;
		while((ent = FindEntityByClassname(ent, "info_target")) != -1) {
			if(IsValidEntity(ent)) {
				char strName[32];
				GetEntPropString(ent, Prop_Data, "m_iName", strName, sizeof(strName));
				if(StrContains(strName, "spawn_loot") != -1) {
					AcceptEntityInput(ent, "Kill");
				}
			}
		}
		char sPos[3][16];
		ExplodeString(sPosition, ",", sPos, sizeof(sPos), sizeof(sPos[]));
		tpos[0] = StringToFloat(sPos[0]);
		tpos[1] = StringToFloat(sPos[1]);
		tpos[2] = StringToFloat(sPos[2]);
		
		for(int i = 0; i < 4; i++) {
			ent = CreateEntityByName("info_target");
			char spawn_name[16];
			Format(spawn_name, sizeof(spawn_name), "%s", i == 0 ? "spawn_loot" : (i == 1 ? "spawn_loot_red" : (i == 2 ? "spawn_loot_blue" : "spawn_boss_alt")));
			SetEntPropString(ent, Prop_Data, "m_iName", spawn_name);
			TeleportEntity(ent, tpos, NULL_VECTOR, NULL_VECTOR);
			DispatchSpawn(ent);
		}
	}
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

public void SetupBossConfigs(const char[] sFile) {
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/%s", sFile);
	
	if(!FileExists(sPath)) {
		LogError("[Boss] Error: Can not find map filepath %s", sPath);
		SetFailState("[Boss] Error: Can not find map filepath %s", sPath);
	}
	Handle kv = CreateKeyValues("Custom Boss Spawner");
	FileToKeyValues(kv, sPath);

	if(!KvGotoFirstSubKey(kv)) {
		LogError("[Boss] Could not read maps file: %s", sPath);
		SetFailState("[Boss] Could not read maps file: %s", sPath);
	}
	gArray.Clear();
	char sName[64], sModel[256], sType[32], sBase[16], sScale[16], sWModel[256], sSize[16], sGlow[8], sPosFix[32];
	char sLifetime[32], sPosition[32], sHorde[8], sColor[16], sISound[256], sDSound[256], sHModel[256], sGnome[8];
	char sHatPosFix[32], sHatSize[16], sDamage[32];
	do {
		KvGetSectionName(kv, sName, sizeof(sName));
		KvGetString(kv, "Model", sModel, sizeof(sModel), SNULL);
		KvGetString(kv, "Type", sType, sizeof(sType));
		KvGetString(kv, "HP Base", sBase, sizeof(sBase), "10000");
		KvGetString(kv, "HP Scale", sScale, sizeof(sScale), "1000");
		KvGetString(kv, "WeaponModel", sWModel, sizeof(sWModel), SNULL);
		KvGetString(kv, "Size", sSize, sizeof(sSize), "1.0");
		KvGetString(kv, "Glow", sGlow, sizeof(sGlow), "Yes");
		KvGetString(kv, "PosFix", sPosFix, sizeof(sPosFix), "0.0");
		KvGetString(kv, "Lifetime", sLifetime, sizeof(sLifetime), "120");
		KvGetString(kv, "Position", sPosition, sizeof(sPosition), SNULL);
		KvGetString(kv, "Horde", sHorde, sizeof(sHorde), "1");
		KvGetString(kv, "Color", sColor, sizeof(sColor), SNULL);
		KvGetString(kv, "IntroSound", sISound, sizeof(sISound), INTRO_SND);
		KvGetString(kv, "DeathSound", sDSound, sizeof(sDSound), DEATH_SND);
		KvGetString(kv, "HatModel", sHModel, sizeof(sHModel), SNULL);
		KvGetString(kv, "Gnome", sGnome, sizeof(sGnome), "0");
		KvGetString(kv, "HatPosFix", sHatPosFix, sizeof(sHatPosFix), "0.0");
		KvGetString(kv, "HatSize", sHatSize, sizeof(sHatSize), "1.0");
		KvGetString(kv, "Damage", sDamage, sizeof(sDamage), "100.0");
		
		if(StrContains(sName, " ") != -1) {
			LogError("[Boss] Boss name should not have spaces, please replace spaces with _");
			SetFailState("[Boss] Boss name should not have spaces, please replace spaces with _");
		}
		if(!StrEqual(sType, HORSEMAN) && !StrEqual(sType, MONOCULUS) && !StrEqual(sType, MERASMUS) && !StrEqual(sType, SKELETON)){
			LogError("[Boss] Type is undetermined, please check boss type again.");
			SetFailState("[Boss] Type is undetermined, please check boss type again.");
		}
		if(!StrEqual(sType, SKELETON)) {
			if(!StrEqual(sHorde, "1")) {
				LogError("[Boss] Horde mode only works for Type: tf_zombie.");
				SetFailState("[Boss] Horde mode only works for Type: tf_zombie.");
			}
			if(strlen(sColor) != 0) {
				LogError("[Boss] Color mode only works for Type: tf_zombie.");
				SetFailState("[Boss] Color mode only works for Type: tf_zombie.");
			}
			if(!StrEqual(sGnome, "0")) {
				LogError("[Boss] Gnome only works for Type: tf_zombie.");
				SetFailState("[Boss] Gnome only works for Type: tf_zombie.");
			}
		}
		if(StrEqual(sType, MONOCULUS)) {
			RemoveBossLifeline("tf_eyeball_boss_lifetime", "tf_eyeball_boss_lifetime", StringToInt(sLifetime)+1);
		}
		else if(StrEqual(sType, MERASMUS)) {
			RemoveBossLifeline("tf_merasmus_lifetime", "tf_merasmus_lifetime", StringToInt(sLifetime)+1);
		}
		if(!StrEqual(sType, HORSEMAN)) {
			if(strlen(sWModel) != 0) {
				LogError("[Boss] Weapon model can only be changed on Type:headless_hatman");
				SetFailState("[Boss] Weapon model can only be changed on Type:headless_hatman");
			}
		}
		else if(strlen(sWModel) != 0) {
			if(!StrEqual(sWModel, "Invisible")) {
				PrecacheModel(sWModel, true);
			}
		}
		if(strlen(sModel) != 0) {
			PrecacheModel(sModel, true);
		}
		if(strlen(sHModel) != 0) {
			PrecacheModel(sHModel, true);
		}
		PrecacheSound(sISound);
		PrecacheSound(sDSound);
		StringMap HashMap = new StringMap();
		HashMap.SetString("Name", sName, false);
		HashMap.SetString("Model", sModel, false);
		HashMap.SetString("Type", sType, false);
		HashMap.SetString("Base", sBase, false);
		HashMap.SetString("Scale", sScale, false);
		HashMap.SetString("WeaponModel", sWModel, false);
		HashMap.SetString("Size", sSize, false);
		HashMap.SetString("Glow", sGlow, false);
		HashMap.SetString("PosFix", sPosFix, false);
		HashMap.SetString("Lifetime", sLifetime, false);
		HashMap.SetString("Position", sPosition, false);
		HashMap.SetString("Horde", sHorde, false);
		HashMap.SetString("Color", sColor, false);
		HashMap.SetString("IntroSound", sISound, false);
		HashMap.SetString("DeathSound", sDSound, false);
		HashMap.SetString("HatModel", sHModel, false);
		HashMap.SetString("Gnome", sGnome, false);
		HashMap.SetString("HatPosFix", sHatPosFix, false);
		HashMap.SetString("HatSize", sHatSize, false);
		HashMap.SetString("Damage", sDamage, false);
		gArray.Push(HashMap);
		char command[64];
		Format(command, sizeof(command), "sm_%s", sName);
		AddCommandListener(SpawnBossCommand, command);
	} while (KvGotoNextKey(kv));
	delete kv;
	LogMessage("[Boss] Custom Boss Spawner Configuration has loaded successfully."); 
}

public void SetupDownloads(const char[] sFile) {
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/%s", sFile);
	
	if(!FileExists(sPath)) {
		LogError("[Boss] Error: Can not find download file %s", sPath);
		SetFailState("[Boss] Error: Can not find download file %s", sPath);
	}
	File file = OpenFile(sPath, "r");
	char buffer[256], fName[128], fPath[256];
	while(!file.EndOfFile() && file.ReadLine(buffer, sizeof(buffer))) {
		int i = -1;
		i = FindCharInString(buffer, '\n', true);
		if(i != -1) buffer[i] = '\0';
		TrimString(buffer);
		//Format(buffer, sizeof(buffer), "%s\\", buffer);
		//PrintToServer("%s", buffer);
		if(!DirExists(buffer)) {
			LogError("[Boss] Error: '%s' directory can not be found.", buffer);
			SetFailState("[Boss] Error: '%s' directory can not be found.", buffer);
		}
		int isMaterial = 0;
		if(StrContains(buffer, "materials/", true) != -1 || StrContains(buffer, "materials\\", true) != -1) {
			isMaterial = 1;
		}
		DirectoryListing sDir = OpenDirectory(buffer, true);
		while(sDir.GetNext(fName, sizeof(fName))) {
			if(StrEqual(fName, ".") || StrEqual(fName, "..")) 
				continue;
			if(StrContains(fName, ".ztmp") != -1) 
				continue;
			if(StrContains(fName, ".bz2") != -1)
				continue;
			Format(fPath, sizeof(fPath), "%s/%s", buffer, fName);
			AddFileToDownloadsTable(fPath);
			if(isMaterial == 1) 
				continue;
			if(StrContains(fName, ".vtx") != -1)
				continue;
			if(StrContains(fName, ".vvd") != -1)
				continue;
			if(StrContains(fName, ".phy") != -1)
				continue;
			PrecacheGeneric(fPath, true);
		}
		delete sDir;
	}
	delete file;
}
/* ---------------------------------CONFIG MANAGEMENT---------------------------------*/

/* ----------------------------------------END----------------------------------------*/