#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <sdkhooks>
#include <multicolors>
#include <emitsoundany>
#include <ttt>
#include <ttt_sql>
#include <config_loader>

#undef REQUIRE_PLUGIN
#tryinclude <sourcebans>

#include "core/globals.sp"
#include "core/natives.sp"
#include "core/sql.sp"

public Plugin myinfo =
{
	name = TTT_PLUGIN_NAME,
	author = TTT_PLUGIN_AUTHOR,
	description = TTT_PLUGIN_DESCRIPTION,
	version = TTT_PLUGIN_VERSION,
	url = TTT_PLUGIN_URL
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// Round forwards
	g_hOnRoundStart_Pre = CreateGlobalForward("TTT_OnRoundStart_Pre", ET_Event);
	g_hOnRoundStart = CreateGlobalForward("TTT_OnRoundStart", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	g_hOnRoundStartFailed = CreateGlobalForward("TTT_OnRoundStartFailed", ET_Ignore, Param_Cell, Param_Cell);
	g_hOnRoundEnd = CreateGlobalForward("TTT_OnRoundEnd", ET_Ignore, Param_Cell);

	g_hOnClientGetRole = CreateGlobalForward("TTT_OnClientGetRole", ET_Ignore, Param_Cell, Param_Cell);

	g_hOnClientDeath = CreateGlobalForward("TTT_OnClientDeath", ET_Ignore, Param_Cell, Param_Cell);

	g_hOnBodyFound = CreateGlobalForward("TTT_OnBodyFound", ET_Ignore, Param_Cell, Param_Cell, Param_String);
	g_hOnBodyChecked = CreateGlobalForward("TTT_OnBodyChecked", ET_Event, Param_Cell, Param_Array);

	g_hOnButtonPress = CreateGlobalForward("TTT_OnButtonPress", ET_Ignore, Param_Cell, Param_Cell);
	g_hOnButtonRelease = CreateGlobalForward("TTT_OnButtonRelease", ET_Ignore, Param_Cell, Param_Cell);

	g_hOnUpdate5 = CreateGlobalForward("TTT_OnUpdate5", ET_Ignore, Param_Cell);
	g_hOnUpdate1 = CreateGlobalForward("TTT_OnUpdate1", ET_Ignore, Param_Cell);

	// Body / Status
	CreateNative("TTT_WasBodyFound", Native_WasBodyFound);
	CreateNative("TTT_WasBodyScanned", Native_WasBodyScanned);
	CreateNative("TTT_GetFoundStatus", Native_GetFoundStatus);
	CreateNative("TTT_SetFoundStatus", Native_SetFoundStatus);

	// Ragdoll
	CreateNative("TTT_GetClientRagdoll", Native_GetClientRagdoll);
	CreateNative("TTT_SetRagdoll", Native_SetRagdoll);

	// Roles
	CreateNative("TTT_GetClientRole", Native_GetClientRole);
	CreateNative("TTT_SetClientRole", Native_SetClientRole);

	// Karma
	CreateNative("TTT_GetClientKarma", Native_GetClientKarma);
	CreateNative("TTT_SetClientKarma", Native_SetClientKarma);
	CreateNative("TTT_AddClientKarma", Native_AddClientKarma);
	CreateNative("TTT_RemoveClientKarma", Native_RemoveClientKarma);

	// Force roles
	CreateNative("TTT_ForceTraitor", Native_ForceTraitor);
	CreateNative("TTT_ForceDetective", Native_ForceDetective);

	// Config
	CreateNative("TTT_OverrideConfigInt", Native_OverrideConfigInt);
	CreateNative("TTT_OverrideConfigBool", Native_OverrideConfigBool);
	CreateNative("TTT_OverrideConfigFloat", Native_OverrideConfigFloat);
	CreateNative("TTT_OverrideConfigString", Native_OverrideConfigString);
	CreateNative("TTT_ReloadConfig", Native_ReloadConfig);

	// Others
	CreateNative("TTT_IsRoundActive", Native_IsRoundActive);
	CreateNative("TTT_LogString", Native_LogString);

	RegPluginLibrary("ttt");

	return APLRes_Success;
}

public void OnPluginStart()
{
	TTT_IsGameCSGO();

	BuildPath(Path_SM, g_sConfigFile, sizeof(g_sConfigFile), "configs/ttt/config.cfg");
	BuildPath(Path_SM, g_sRulesFile, sizeof(g_sRulesFile), "configs/ttt/rules/start.cfg");

	LoadTranslations("ttt.phrases");
	LoadTranslations("common.phrases");

	LoadBadNames();

	g_aRagdoll = new ArrayList(104);
	g_aLogs = new ArrayList(512);

	g_aForceTraitor = new ArrayList();
	g_aForceDetective = new ArrayList();

	g_iCollisionGroup = FindSendPropInfo("CBaseEntity", "m_CollisionGroup");

	CreateTimer(1.0, Timer_1, _, TIMER_REPEAT);
	CreateTimer(5.0, Timer_5, _, TIMER_REPEAT);
	
	// Admin commands
	RegConsoleCmd("sm_setrole", Command_SetRole);
	RegConsoleCmd("sm_karmareset", Command_KarmaReset);
	RegConsoleCmd("sm_setkarma", Command_SetKarma);
	RegConsoleCmd("sm_reloadcfg", Command_ReloadCFG);

	RegConsoleCmd("sm_status", Command_Status);
	RegConsoleCmd("sm_karma", Command_Karma);

	RegConsoleCmd("sm_logs", Command_Logs);
	RegConsoleCmd("sm_log", Command_Logs);

	RegConsoleCmd("sm_trules", Command_TRules);
	RegConsoleCmd("sm_drules", Command_DetectiveRules);

	HookEvent("player_death", Event_PlayerDeathPre, EventHookMode_Pre);
	HookEvent("round_prestart", Event_RoundStartPre, EventHookMode_Pre);
	HookEvent("round_end", Event_RoundEndPre, EventHookMode_Pre);
	HookEvent("player_spawn", Event_PlayerSpawn_Pre, EventHookMode_Pre);
	HookEvent("player_team", Event_PlayerTeam_Pre, EventHookMode_Pre);

	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_changename", Event_ChangeName);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_hurt", Event_PlayerHurt);

	g_hGraceTime = FindConVar("mp_join_grace_time");

	AddCommandListener(Command_LAW, "+lookatweapon");
	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_SayTeam, "say_team");
	AddCommandListener(Command_InterceptSuicide, "kill");
	AddCommandListener(Command_InterceptSuicide, "explode");
	AddCommandListener(Command_InterceptSuicide, "spectate");
	AddCommandListener(Command_InterceptSuicide, "jointeam");
	AddCommandListener(Command_InterceptSuicide, "joinclass");

	for (int i = 0; i < sizeof(g_sRadioCMDs); i++)
	{
		AddCommandListener(Command_RadioCMDs, g_sRadioCMDs[i]);
	}

	SetupConfig();

	if (TTT_GetSQLConnection() != null)
	{
		LateLoadClients(true);
	}
	
	g_uMessage = GetUserMessageId("TextMsg");
	
	if (g_uMessage)
	{
		HookUserMessage(g_uMessage, UserMessage_TextMsg, true);
	}
}

public void OnAllPluginsLoaded()
{
	if (LibraryExists("sourcebans"))
	{
		g_bSourcebans = true;
	}
}

public void OnLibraryAdded(const char[] library)
{
	if (StrEqual(library, "sourcebans", false))
	{
		g_bSourcebans = true;
	}
}

public void OnLibraryRemoved(const char[] library)
{
	if (StrEqual(library, "sourcebans", false))
	{
		g_bSourcebans = false;
	}
}

public void TTT_OnSQLConnect(Database db)
{
	g_dDB = db;

	LateLoadClients(false);
}

void SetupConfig()
{
	CreateConVar("ttt2_version", TTT_PLUGIN_VERSION, TTT_PLUGIN_DESCRIPTION, FCVAR_NOTIFY | FCVAR_DONTRECORD);

	Config_Setup("TTT", g_sConfigFile);

	// Karma settings
	g_iConfig[bshowKarmaOnSpawn] = Config_LoadBool("ttt_show_karma_on_spawn", true, "Show players karma on spawn?");
	g_iConfig[bshowEarnKarmaMessage] = Config_LoadBool("ttt_show_message_earn_karma", true, "Display a message showing how much karma you earned. 1 = Enabled, 0 = Disabled");
	g_iConfig[bshowLoseKarmaMessage] = Config_LoadBool("ttt_show_message_lose_karma", true, "Display a message showing how much karma you lost. 1 = Enabled, 0 = Disabled");
	g_iConfig[bpublicKarma] = Config_LoadBool("ttt_public_karma", false, "Show karma as points (or another way?)");
	g_iConfig[bkarmaRound] = Config_LoadBool("ttt_private_karma_round_update", true, "If ttt_public_karma is not set to 1, enable this to update karma at end of round.");
	g_iConfig[bkarmaDMG] = Config_LoadBool("ttt_karma_dmg", false, "Scale damage based off of karma? (damage *= (karma/startkarma))");
	g_iConfig[bkarmaDMG_up] = Config_LoadBool("ttt_karma_dmg_up", false, "If ttt_karma_dmg is enabled, should be enable scaling damage upward?");
	g_iConfig[imessageTypKarma] = Config_LoadInt("ttt_message_typ_karma", 1, "The karma message type. 1 = Hint Text or 2 = Chat Message");
	g_iConfig[ikarmaII] = Config_LoadInt("ttt_karma_killer_innocent_victim_innocent_subtract", 5, "The amount of karma an innocent will lose for killing an innocent.");
	g_iConfig[ikarmaIT] = Config_LoadInt("ttt_karma_killer_innocent_victim_traitor_add", 5, "The amount of karma an innocent will recieve for killing a traitor.");
	g_iConfig[ikarmaID] = Config_LoadInt("ttt_karma_killer_innocent_victim_detective_subtract", 7, "The amount of karma an innocent will lose for killing a detective.");
	g_iConfig[ikarmaTI] = Config_LoadInt("ttt_karma_killer_traitor_victim_innocent_add", 2, "The amount of karma a traitor will recieve for killing an innocent.");
	g_iConfig[ikarmaTT] = Config_LoadInt("ttt_karma_killer_traitor_victim_traitor_subtract", 5, "The amount of karma a traitor will lose for killing a traitor.");
	g_iConfig[ikarmaTD] = Config_LoadInt("ttt_karma_killer_traitor_victim_detective_add", 3, "The amount of karma a traitor will recieve for killing a detective.");
	g_iConfig[ikarmaDI] = Config_LoadInt("ttt_karma_killer_detective_victim_innocent_subtract", 3, "The amount of karma a detective will lose for killing an innocent.");
	g_iConfig[ikarmaDT] = Config_LoadInt("ttt_karma_killer_detective_victim_traitor_add", 7, "The amount of karma a detective will recieve for killing a traitor.");
	g_iConfig[ikarmaDD] = Config_LoadInt("ttt_karma_killer_detective_victim_detective_subtract", 7, "The amount of karma a detective will lose for killing a detective.");
	g_iConfig[istartKarma] = Config_LoadInt("ttt_start_karma", 100, "The amount of karma new players and players who were karma banned will start with.");
	g_iConfig[ikarmaBan] = Config_LoadInt("ttt_with_karma_ban", 75, "The amount of karma needed to be banned for Bad Karma. (0 = Disabled)");
	g_iConfig[ikarmaBanLength] = Config_LoadInt("ttt_with_karma_ban_length", 10080, "The length of a Bad Karma ban. (Default = 1 Week)");
	g_iConfig[imaxKarma] = Config_LoadInt("ttt_max_karma", 150, "The maximum amount of karma a player can have.");
	g_iConfig[irequiredPlayersD] = Config_LoadInt("ttt_required_players_detective", 6, "The amount of players required to activate the detective role.");
	g_iConfig[irequiredPlayers] = Config_LoadInt("ttt_required_player", 3, "The amount of players required to start the game.");
	g_iConfig[imaxTraitors] = Config_LoadInt("ttt_traitor_max", 32, "Maximum number of traitors. Customize this if you want to finetune the number of traitors at your server's max playercount, for example to make sure there are max 3 traitors on a 16 player server.");
	g_iConfig[imaxDetectives] = Config_LoadInt("ttt_detective_max", 32, "Maximum number of detectives. Can be used to cap or disable detectives.");
	g_iConfig[iminKarmaDetective] = Config_LoadInt("ttt_detective_karma_min", 100, "If a player's Karma falls below this point, his chances of being selected as detective are reduced.");

	g_iConfig[bblockSuicide] = Config_LoadBool("ttt_block_suicide", false, "Block players from suiciding with console. 1 = Block, 0 = Don't Block");
	g_iConfig[bblockRadioMessage] = Config_LoadBool("ttt_block_radio_message", true, "Block radio messages in chat. 1 = Block, 0 = Don't Block");
	g_iConfig[bshowDeathMessage] = Config_LoadBool("ttt_show_death_message", true, "Display a message showing who killed you. 1 = Enabled, 0 = Disabled");
	g_iConfig[bshowKillMessage] = Config_LoadBool("ttt_show_kill_message", true, "Display a message showing who you killed. 1 = Enabled, 0 = Disabled");
	g_iConfig[ballowFlash] = Config_LoadBool("ttt_allow_flash", true, "Enable Flashlight (+lookatweapon). 1 = Enabled, 0 Disabled");
	g_iConfig[bblockLookAtWeapon] = Config_LoadBool("ttt_block_look_at_weapon", true, "Block weapon inspecting. 1 = Block, 0 = Don't Block)");
	g_iConfig[benableNoBlock] = Config_LoadBool("ttt_enable_noblock", false, "Enable No Block. 1 = Enabled, 0 = Disabled");
	g_iConfig[bkadRemover] = Config_LoadBool("ttt_kad_remover", true, "Block kills, deaths and assists from appearing on the scoreboard. 1 = Enabled, 0 = Disabled");
	g_iConfig[ifakeHealth] = Config_LoadInt("ttt_fake_health", 100, "TODO: Add description");
	g_iConfig[ifakeLife] = Config_LoadInt("ttt_fake_life", 0, "TODO: Add description (0 - default, 1 - everyone is dead, 2 - everyone is alive)");
	Config_LoadString("ttt_plugin_tag", "{orchid}[{green}T{darkred}T{blue}T{orchid}]{lightgreen} %T", "The prefix used in all plugin messages (DO NOT DELETE '%T')", g_iConfig[spluginTag], sizeof(g_iConfig[spluginTag]));
	g_iConfig[ispawnHPT] = Config_LoadInt("ttt_spawn_t", 100, "The amount of health traitors spawn with. ( 0 = disabled )");
	g_iConfig[ispawnHPD] = Config_LoadInt("ttt_spawn_d", 100, "The amount of health detectives spawn with. ( 0 = disabled )");
	g_iConfig[ispawnHPI] = Config_LoadInt("ttt_spawn_i", 100, "The amount of health innocents spawn with. ( 0 = disabled )");
	g_iConfig[irulesClosePunishment] = Config_LoadInt("ttt_rules_close_punishment", 0, "The punishment for abusing the rules menu by closing it with another menu. 0 = Kick, Anything Else = Do Nothing");
	g_iConfig[itimeToReadDetectiveRules] = Config_LoadInt("ttt_time_to_read_detective_rules", 15, "The time in seconds the detective rules menu will stay open.");
	g_iConfig[itimeToReadRules] = Config_LoadInt("ttt_time_to_read_rules", 30, "The time in seconds the general rules menu will stay open.");
	g_iConfig[bshowDetectiveMenu] = Config_LoadBool("ttt_show_detective_menu", true, "Show the detective menu. 1 = Show, 0 = Don't Show");
	g_iConfig[bshowRulesMenu] = Config_LoadBool("ttt_show_rules_menu", true, "Show the rules menu. 1 = Show, 0 Don't Show");
	g_iConfig[ipunishInnoKills] = Config_LoadInt("ttt_punish_innocent_for_rdm_kils", 3, "The amount of times an innocent will be allowed to kill another innocent/detective before being punished for RDM.");
	g_iConfig[ipunishTraitorKills] = Config_LoadInt("ttt_punish_traitor_for_rdm_kils", 1, "The amount of times an traitor will be allowed to kill another traitor before being punished for RDM.");
	g_iConfig[ipunishDetectiveKills] = Config_LoadInt("ttt_punish_detective_for_rdm_kils", 5, "The amount of times an detective will be allowed to kill another innocent/detective before being punished for RDM.");
	Config_LoadString("ttt_kick_immunity", "b", "Admin flags that won't be kicked for not reading the rules.", g_iConfig[skickImmunity], sizeof(g_iConfig[skickImmunity]));
	Config_LoadString("ttt_logsaccess", "b", "Admin flags to view logs in a round.", g_iConfig[slogsAccess], sizeof(g_iConfig[slogsAccess]));
	g_iConfig[bLogsDeadOnly] = Config_LoadBool("ttt_logs_dead_only", false, "Access to logs only for dead admins?");
	g_iConfig[bLogsNotifyAlive] = Config_LoadInt("ttt_logs_notify_alive", 1, "Notify if logs has been watched by alive admin. 0 = Don't notify anyone, 1 = Notify everyone, 2 = Notify admins only");
	g_iConfig[bupdateClientModel] = Config_LoadBool("ttt_update_client_model", true, "Update the client model isntantly when they are assigned a role. Disables forcing client models to a specified model. 1 = Update, 0 = Don't Update");
	g_iConfig[bremoveHostages] = Config_LoadBool("ttt_remove_hostages", true, "Remove all hostages from the map to prevent interference. 1 = Remove, 0 = Don't Remove");
	g_iConfig[bremoveBomb] = Config_LoadBool("ttt_remove_bomb_on_spawn", true, "Remove the bomb spots from the map to prevent interference. 1 = Remove, 0 = Don't Remove");
	g_iConfig[broleAgain] = Config_LoadBool("ttt_role_again", false, "Allow getting the same role twice in a row.");
	g_iConfig[itraitorRatio] = Config_LoadInt("ttt_traitor_ratio", 25, "The chance of getting the traitor role.");
	g_iConfig[idetectiveRatio] = Config_LoadInt("ttt_detective_ratio", 13, "The chance of getting the detective role.");
	g_iConfig[bdenyFire] = Config_LoadBool("ttt_deny_fire", true, "Stop players who have not been assigned a role yet from shooting. (Mouse1 & Mouse2)");
	g_iConfig[bslayAfterStart] = Config_LoadBool("ttt_slay_after_start", true, "Slay all players after ttt round started");
	g_iConfig[bremoveBuyzone] = Config_LoadBool("ttt_disable_buyzone", false, "Remove all buyzones from the map to prevent interference. 1 = Remove, 0 = Don't Remove");
	g_iConfig[bforceTeams] = Config_LoadBool("ttt_force_teams", true, "Force players to teams instead of forcing playermodel. 1 = Force team. 0 = Force playermodel.");
	g_iConfig[brandomWinner] = Config_LoadBool("ttt_random_winner", true, "Choose random winner (CT/T) regardless of normal result. 1 = Yes, 0 = No");
	g_iConfig[bforceModel] = Config_LoadBool("ttt_force_models", false, "Force all players to use a specified playermodel. Not functional if update models is enabled. 1 = Force models. 0 = Disabled (default).");
	g_iConfig[bendwithD] = Config_LoadBool("ttt_end_with_detective", false, "Allow the round to end if Detectives remain alive. 0 = Disabled (default). 1 = Enabled.");
	g_iConfig[bhideTeams] = Config_LoadBool("ttt_hide_teams", false, "Hide team changes from chat.");

	g_iConfig[bstripWeapons] = Config_LoadBool("ttt_strip_weapons", true, "Strip players weapons on spawn? Optionally use mp_ct_ and mp_t_ cvars instead.");
	g_iConfig[f_roundDelay] = Config_LoadFloat("ttt_after_round_delay", 7.0, "The amount of seconds to use for round-end delay. Use 0.0 for default.");
	g_iConfig[bnextRoundAlert] = Config_LoadBool("ttt_next_round_alert", false, "Tell players in chat when the next round will begin (when the round ends)");
	g_iConfig[bignoreDeaths] = Config_LoadBool("ttt_ignore_deaths", false, "Ignore deaths (longer rounds)? 0 = Disabled (default). 1 = Enabled.");
	g_iConfig[bignoreRDMMenu] = Config_LoadBool("ttt_ignore_rdm_slay", false, "Don't ask players to forgive/punish other players (rdm'd). 0 = Disabled (default). 1 = Enabled.");
	g_iConfig[bdeadPlayersCanSeeOtherRules] = Config_LoadBool("ttt_dead_players_can_see_other_roles", false, "Allow dead players to see other roles. 0 = Disabled (default). 1 = Enabled.");
	g_iConfig[btChatToDead] = Config_LoadBool("ttt_t_chat_to_dead", false, "Show traitor chat messages to dead players?");
	g_iConfig[bdChatToDead] = Config_LoadBool("ttt_d_chat_to_dead", false, "Show detective chat messages to dead players?");
	g_iConfig[bTranfserArmor] = Config_LoadBool("ttt_transfer_armor", false, "Save armor on round end for living players and re-set in the next round?");
	g_iConfig[bRespawnDeadPlayers] = Config_LoadBool("ttt_respawn_dead_players", true, "Respawn dead players on pre role selection?");
	g_iConfig[bEnableDamage] = Config_LoadBool("ttt_prestart_damage", false, "Enable damage before round start (Default disabled to prevent kills)?");
	g_iConfig[broundendDamage] = Config_LoadBool("ttt_roundend_dm", false, "Enable damage after a round until round end.");
	g_iConfig[bHideTeamAttackMessage] = Config_LoadBool("ttt_hide_team_attack_message", true, "Hide team attack messages");

	Config_LoadString("ttt_forced_model_ct", "models/player/ctm_st6.mdl", "The default model to force for CT (Detectives) if ttt_force_models is enabled.", g_iConfig[smodelCT], sizeof(g_iConfig[smodelCT]));
	Config_LoadString("ttt_forced_model_t", "models/player/tm_phoenix.mdl", "The default model to force for T (Inno/Traitor) if ttt_force_models is enabled.", g_iConfig[smodelT], sizeof(g_iConfig[smodelT]));

	Config_LoadString("ttt_log_file", "logs/ttt/ttt-<DATE>.log", "The default file to log TTT data to (including end of round) - DON'T REMOVE \"-<DATE>\" IF YOU DON'T KNOW WHAT YOU DO.", g_iConfig[slogFile], sizeof(g_iConfig[slogFile]));
	Config_LoadString("ttt_error_file", "logs/ttt/ttt-error-<DATE>.log", "The default file to log TTT errors/bugs to - DON'T REMOVE \"-<DATE>\" IF YOU DON'T KNOW WHAT YOU DO.", g_iConfig[serrFile], sizeof(g_iConfig[serrFile]));
	Config_LoadString("ttt_log_date_format", "%y-%m-%d", "Date format for the log files", g_iConfig[slogDateFormat], sizeof(g_iConfig[slogDateFormat]));

	// Move to ttt_weapons
	Config_LoadString("ttt_default_primary_d", "weapon_m4a1_silencer", "The default primary gun to give players when they become a Detective (if they have no primary).", g_iConfig[sdefaultPriD], sizeof(g_iConfig[sdefaultPriD]));
	Config_LoadString("ttt_default_secondary", "weapon_glock", "The default secondary gun to give players when they get their role (if they have no secondary).", g_iConfig[sdefaultSec], sizeof(g_iConfig[sdefaultSec]));

	g_iConfig[iRoundStartedFontSize] = Config_LoadInt("ttt_round_started_font_size", 32, "Font size of the text if round started");
	Config_LoadString("ttt_round_started_font_color", "44ff22", "Font color (hexcode without hastag!) of the text if round started", g_iConfig[sRoundStartedFontColor], sizeof(g_iConfig[sRoundStartedFontColor]));
	g_iConfig[iRoundStartFontSize] = Config_LoadInt("ttt_round_start_font_size", 24, "Font size of the text while the countdown runs");
	Config_LoadString("ttt_round_start_font_color", "ffA500", "Font color (hexcode without hastag!) of the text while the countdown runs", g_iConfig[sRoundStartFontColor], sizeof(g_iConfig[sRoundStartFontColor]));
	g_iConfig[bShowTraitors] = Config_LoadBool("ttt_show_traitor_names", true, "Show traitor partners on team selection?");

	g_iConfig[bGiveWeaponsOnFailStart] = Config_LoadBool("ttt_give_weapons_on_failed_start", false, "Give player weapons on a fail start?");
	Config_LoadString("ttt_give_weapons_fail_start_primary", "ak47", "What primary weapon do you want? (WITHOUT 'weapon_' TAG!)", g_iConfig[sFSPrimary], sizeof(g_iConfig[sFSPrimary]));
	Config_LoadString("ttt_give_weapons_fail_start_secondary", "deagle", "What primary weapon do you want? (WITHOUT 'weapon_' TAG!)", g_iConfig[sFSSecondary], sizeof(g_iConfig[sFSSecondary]));
	
	Config_LoadString("ttt_command_access_setsole", "d", "Admin flags to access the 'setrole' command.", g_iConfig[sSetRole], sizeof(g_iConfig[sSetRole]));
	Config_LoadString("ttt_command_access_karmareset", "m", "Admin flags to access the 'karmareset' command.", g_iConfig[sKarmaReset], sizeof(g_iConfig[sKarmaReset]));
	Config_LoadString("ttt_command_access_setkarma", "m", "Admin flags to access the 'setkarma' command.", g_iConfig[sSetKerma], sizeof(g_iConfig[sSetKerma]));
	Config_LoadString("ttt_command_access_reloadcfg", "i", "Admin flags to access the 'reloadcfg' command.", g_iConfig[sReloadCFG], sizeof(g_iConfig[sReloadCFG]));
	
	g_iConfig[bAddSteamIDtoLogs] = Config_LoadBool("ttt_steamid_add_to_logs", true, "Should we add steam id to all log actions? Prevent abusing with namefakers");
	g_iConfig[iSteamIDLogFormat] = Config_LoadInt("ttt_steamid_log_format", 1, "Which steam id format to you prefer? 1 - SteamID2 (STEAM_1:1:40828751), 2 - SteamID3 ([U:1:81657503]) or 3 - SteamID64/CommunityID (76561198041923231)");

	g_iConfig[bDebugMessages] = Config_LoadBool("ttt_show_debug_messages", false, "Show debug messages to all root admins?");
	
	Config_Remove("ttt_show_rulesmenu");
	Config_Remove("ttt_show__message_lose_karmna");
	Config_Remove("ttt_show_message_lose_karmna");
	Config_Remove("ttt_required_playersdetective");
	Config_Remove("ttt_rulesclose_punishment");
	Config_Remove("ttt_logsdead_only");
	Config_Remove("ttt_logsnotify_alive");
	Config_Remove("ttt_remove_bombon_spawn");
	Config_Remove("ttt_dead_playerscan_see_other_roles");
	Config_Remove("ttt_give_weaponson_failed_start");
	Config_Remove("ttt_give_weaponsfail_start_primary");
	Config_Remove("ttt_give_weaponsfail_start_secondary");
	Config_Remove("ttt_block_grenade_message");

	Config_Done();

	char sDate[12];
	FormatTime(sDate, sizeof(sDate), g_iConfig[slogDateFormat]);
	ReplaceString(g_iConfig[slogFile], sizeof(g_iConfig[slogFile]), "<DATE>", sDate, true);
	ReplaceString(g_iConfig[serrFile], sizeof(g_iConfig[serrFile]), "<DATE>", sDate, true);

	BuildPath(Path_SM, g_iConfig[slogFile], sizeof(g_iConfig[slogFile]), g_iConfig[slogFile]);
	BuildPath(Path_SM, g_iConfig[serrFile], sizeof(g_iConfig[serrFile]), g_iConfig[serrFile]);
}

public Action Command_Logs(int client, int args)
{
	if (g_bRoundEnding || g_bRoundStarted)
	{
		if (client == 0)
		{
			ShowLogs(client);
		}
		else if (TTT_IsClientValid(client) && TTT_HasFlags(client, g_iConfig[slogsAccess]))
		{
			if (g_iConfig[bLogsDeadOnly])
			{
				if (!IsPlayerAlive(client))
				{
					ShowLogs(client);
				}
			}
			else
			{
				ShowLogs(client);
				
				if (g_iConfig[bLogsNotifyAlive] > 0 && !g_bRoundEnding && IsPlayerAlive(client))
				{
					if (g_iConfig[bLogsNotifyAlive] == 1)
					{
						LoopValidClients(j)
						{
							CPrintToChat(j, g_iConfig[spluginTag], "watching logs alive", j, client);
						}
					}
					else if (g_iConfig[bLogsNotifyAlive] == 2)
					{
						LoopValidClients(j)
						{
							if (TTT_HasFlags(j, g_iConfig[slogsAccess]))
							{
								CPrintToChat(j, g_iConfig[spluginTag], "watching logs alive", j, client);
							}
						}
					}
				}
			}
		}
		return Plugin_Continue;
	}

	CPrintToChat(client, g_iConfig[spluginTag], "you cant see logs", client);
	return Plugin_Handled;
}

stock void ShowLogs(int client)
{
	int iSize = g_aLogs.Length;
	if (iSize == 0)
	{
		if (client == 0)
		{
			PrintToServer("No logs yet");
		}
		else
		{
			CPrintToChat(client, g_iConfig[spluginTag], "no logs yet", client);
		}

		return;
	}

	if (g_bReceivingLogs[client])
	{
		return;
	}

	g_bReceivingLogs[client] = true;

	if (client == 0)
	{
		LogToFileEx(g_iConfig[slogFile], "--------------------------------------");
		LogToFileEx(g_iConfig[slogFile], "-----------START ROUND LOGS-----------");
	}
	else
	{
		CPrintToChat(client, g_iConfig[spluginTag], "Receiving logs", client);
		PrintToConsole(client, "--------------------------------------");
		PrintToConsole(client, "---------------TTT LOGS---------------");
	}

	char iItem[TTT_ITEM_SIZE];
	int index = 5;
	bool end = false;

	if (index >= iSize)
	{
		end = true;
		index = (iSize - 1);
	}

	for (int i = 0; i <= index; i++)
	{
		g_aLogs.GetString(i, iItem, sizeof(iItem));

		if (client == 0)
		{
			LogToFileEx(g_iConfig[slogFile], iItem);
		}
		else
		{
			PrintToConsole(client, iItem);
		}
	}

	if (end)
	{
		if (client == 0)
			LogToFileEx(g_iConfig[slogFile], "--------------------------------------");
		else
		{
			CPrintToChat(client, g_iConfig[spluginTag], "See your console", client);
			PrintToConsole(client, "--------------------------------------");
			PrintToConsole(client, "--------------------------------------");
		}

		g_bReceivingLogs[client] = false;
		return;
	}

	Handle slPack = CreateDataPack();

	if (TTT_IsClientValid(client))
	{
		WritePackCell(slPack, GetClientUserId(client));
	}
	else
	{
		WritePackCell(slPack, 0);
	}

	WritePackCell(slPack, index);
	RequestFrame(OnCreate, slPack);
}

public void OnCreate(any data)
{
	ResetPack(data);

	int userid = ReadPackCell(data);
	int index = ReadPackCell(data);

	if (view_as<Handle>(data) != null)
	{
		delete view_as<Handle>(data);
	}

	int client;
	if (userid == 0)
	{
		client = userid;
	}
	else
	{
		client = GetClientOfUserId(userid);
	}

	if ((client == 0) || IsClientInGame(client))
	{
		int sizearray = g_aLogs.Length;
		int old = (index + 1);
		index += 5;
		bool end = false;

		if (index >= sizearray)
		{
			end = true;
			index = (sizearray - 1);
		}

		char iItem[TTT_ITEM_SIZE];

		for (int i = old; i <= index; i++)
		{
			g_aLogs.GetString(i, iItem, sizeof(iItem));

			if (client == 0)
			{
				LogToFileEx(g_iConfig[slogFile], iItem);
			}
			else
			{
				PrintToConsole(client, iItem);
			}
		}

		if (end)
		{
			if (client == 0)
				LogToFileEx(g_iConfig[slogFile], "--------------------------------------");
			else
			{
				CPrintToChat(client, g_iConfig[spluginTag], "See your console", client);
				PrintToConsole(client, "--------------------------------------");
				PrintToConsole(client, "--------------------------------------");
			}

			g_bReceivingLogs[client] = false;
			return;
		}

		Handle slPack = CreateDataPack();

		if (TTT_IsClientValid(client))
		{
			WritePackCell(slPack, GetClientUserId(client));
		}
		else
		{
			WritePackCell(slPack, 0);
		}

		WritePackCell(slPack, index);
		RequestFrame(OnCreate, slPack);
	}
}

public Action Command_InterceptSuicide(int client, const char[] command, int args)
{
	if (g_iConfig[bblockSuicide] && IsPlayerAlive(client))
	{
		CPrintToChat(client, g_iConfig[spluginTag], "Suicide Blocked", client);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action Command_RadioCMDs(int client, const char[] command, int args)
{
	if (g_iConfig[bblockRadioMessage])
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public void OnMapStart()
{
	for (int i; i < g_iBadNameCount; i++)
	{
		g_sBadNames[i] = "";
	}
	g_iBadNameCount = 0;

	LoadBadNames();

	g_iBeamSprite = PrecacheModel("materials/sprites/bomb_planted_ring.vmt");
	g_iHaloSprite = PrecacheModel("materials/sprites/halo.vtf");

	PrecacheModel("props/cs_office/microwave.mdl", true);

	PrecacheSoundAny(SND_TCHAT, true);
	PrecacheSoundAny(SND_FLASHLIGHT, true);

	if (g_aLogs != null)
		g_aLogs.Clear();

	PrecacheModel(g_iConfig[smodelCT], true);
	PrecacheModel(g_iConfig[smodelT], true);

	g_iAlive = FindSendPropInfo("CCSPlayerResource", "m_bAlive");
	if (g_iAlive == -1)
	{
		SetFailState("CCSPlayerResource \"m_bAlive\" offset is invalid");
	}
	
	g_iHealth = FindSendPropInfo("CCSPlayerResource", "m_iHealth");
	if (g_iHealth == -1)
	{
		SetFailState("CCSPlayerResource \"m_iHealth\" offset is invalid");
	}

	g_iKills = FindSendPropInfo("CCSPlayerResource", "m_iKills");
	if (g_iKills == -1)
	{
		SetFailState("CCSPlayerResource \"m_iKills\" offset is invalid");
	}

	g_iDeaths = FindSendPropInfo("CCSPlayerResource", "m_iDeaths");
	if (g_iDeaths == -1)
	{
		SetFailState("CCSPlayerResource \"m_iDeaths\"  offset is invalid");
	}

	g_iAssists = FindSendPropInfo("CCSPlayerResource", "m_iAssists");
	if (g_iAssists == -1)
	{
		SetFailState("CCSPlayerResource \"m_iAssists\"  offset is invalid");
	}

	g_iMVPs = FindSendPropInfo("CCSPlayerResource", "m_iMVPs");
	if (g_iMVPs == -1)
	{
		SetFailState("CCSPlayerResource \"m_iMVPs\"  offset is invalid");
	}

	SDKHook(FindEntityByClassname(0, "cs_player_manager"), SDKHook_ThinkPost, ThinkPost);
}

public void ThinkPost(int entity)
{
	if (g_iConfig[bkadRemover])
	{
		int iZero[MAXPLAYERS + 1] =  { 0, ... };
		
		SetEntDataArray(entity, g_iKills, iZero, MaxClients + 1);
		SetEntDataArray(entity, g_iDeaths, iZero, MaxClients + 1);
		SetEntDataArray(entity, g_iAssists, iZero, MaxClients + 1);
		SetEntDataArray(entity, g_iMVPs, iZero, MaxClients + 1);
	}
	
	int isAlive[MAXPLAYERS + 1];
	int iHealth[MAXPLAYERS + 1];

	GetEntDataArray(entity, g_iAlive, isAlive, MAXPLAYERS + 1);
	
	LoopValidClients(i)
	{
		if (g_iConfig[ifakeLife] == 0)
		{
			isAlive[i] = (!g_bFound[i]);
		}
		else if (g_iConfig[ifakeLife] == 1)
		{
			isAlive[i] = false;
		}
		else if (g_iConfig[ifakeLife] == 2)
		{
			isAlive[i] = true;
		}
		
		iHealth[i] = g_iConfig[ifakeHealth];
	}
	
	SetEntDataArray(entity, g_iHealth, iHealth, MAXPLAYERS + 1);
	SetEntDataArray(entity, g_iAlive, isAlive, MAXPLAYERS + 1);
}

public Action Command_Karma(int client, int args)
{
	if (!TTT_IsClientValid(client))
	{
		return Plugin_Handled;
	}

	CPrintToChat(client, g_iConfig[spluginTag], "Your karma is", client, g_iKarma[client]);

	return Plugin_Handled;
}

public Action Event_RoundStartPre(Event event, const char[] name, bool dontBroadcast)
{
	if (g_aRagdoll != null)
	{
		g_aRagdoll.Clear();
	}

	g_bInactive = false;
	g_bRoundEnded = false;

	LoopValidClients(i)
	{
		g_iRole[i] = TTT_TEAM_UNASSIGNED;
		g_bFound[i] = true;
		g_iInnoKills[i] = 0;
		g_iTraitorKills[i] = 0;
		g_iDetectiveKills[i] = 0;
		g_bImmuneRDMManager[i] = false;

		CS_SetClientClanTag(i, " ");
	}

	if (g_hStartTimer != null)
	{
		KillTimer(g_hStartTimer);
	}

	if (g_hCountdownTimer != null)
	{
		KillTimer(g_hCountdownTimer);
	}

	float warmupTime = GetConVarFloat(g_hGraceTime) + 5.0;
	g_hStartTimer = CreateTimer(warmupTime, Timer_Selection, _, TIMER_FLAG_NO_MAPCHANGE);

	g_fRealRoundStart = GetGameTime() + warmupTime;
	g_hCountdownTimer = CreateTimer(0.5, Timer_SelectionCountdown, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	g_bRoundStarted = false;

	if (g_hRoundTimer != null)
	{
		delete g_hRoundTimer;
	}

	g_hRoundTimer = CreateTimer(GetConVarFloat(FindConVar("mp_freezetime")) + (GetConVarFloat(FindConVar("mp_roundtime")) * 60.0), Timer_OnRoundEnd);
}

public Action Event_RoundEndPre(Event event, const char[] name, bool dontBroadcast)
{
	LoopValidClients(i)
	{
		g_bFound[i] = true;
		g_iInnoKills[i] = 0;
		g_iTraitorKills[i] = 0;
		g_iDetectiveKills[i] = 0;
		g_bImmuneRDMManager[i] = false;

		ShowLogs(i);
		TeamTag(i);

		if (g_iConfig[bTranfserArmor])
		{
			if (IsPlayerAlive(i))
			{
				g_iArmor[i] = GetEntProp(i, Prop_Send, "m_ArmorValue");
			}
		}
	}

	ShowLogs(0);

	g_iTeamSelectTime = 0;
	g_bSelection = false;

	if (g_hRoundTimer != null)
	{
		delete g_hRoundTimer;
		g_hRoundTimer = null;
	}
}

public Action Timer_SelectionCountdown(Handle hTimer)
{
	int timeLeft = RoundToFloor(g_fRealRoundStart - GetGameTime());
	char centerText[512];

	if (g_fRealRoundStart <= 0.0 || timeLeft <= 0)
	{
		if (timeLeft == 0)
		{
			LoopValidClients(i)
			{
				Format(centerText, sizeof(centerText), "%T", "RoundStartedCenter", i, g_iConfig[iRoundStartedFontSize], g_iConfig[sRoundStartedFontColor]);
				PrintHintText(i, centerText);
			}
		}

		g_hCountdownTimer = null;
		return Plugin_Stop;
	}

	LoopValidClients(i)
	{
		Format(centerText, sizeof(centerText), "%T", "RoundStartCenter", i, g_iConfig[iRoundStartFontSize], g_iConfig[sRoundStartFontColor], timeLeft);
		PrintHintText(i, centerText);
	}

	return Plugin_Continue;
}

public Action Timer_Selection(Handle hTimer)
{
	g_bRoundEnding = false;
	g_hStartTimer = null;


	ArrayList aPlayers = new ArrayList(1);

	LoopValidClients(i)
	{
		if (GetClientTeam(i) != CS_TEAM_CT && GetClientTeam(i) != CS_TEAM_T  || (!g_bDebug && IsFakeClient(i)))
		{
			continue;
		}

		if (!IsPlayerAlive(i))
		{
			if (g_iConfig[bRespawnDeadPlayers])
			{
				CS_RespawnPlayer(i);
			}
			else
			{
				continue;
			}
		}

		aPlayers.Push(i);
	}

	Action res = Plugin_Continue;
	Call_StartForward(g_hOnRoundStart_Pre);
	Call_Finish(res);

	if (res >= Plugin_Handled)
	{
		Call_StartForward(g_hOnRoundStartFailed);
		Call_PushCell(-1);
		Call_PushCell(g_iConfig[irequiredPlayers]);
		Call_Finish();

		GiveWeaponsOnFailStart();

		return;
	}

	//Check if there are any slain players
	for (int i = 0; i < aPlayers.Length; i++)
	{
		if(!IsPlayerAlive(aPlayers.Get(i)))
			aPlayers.Erase(i--);
	}

	if (aPlayers.Length < g_iConfig[irequiredPlayers])
	{
		g_bInactive = true;
		LoopValidClients(i)
		{
			CPrintToChat(i, g_iConfig[spluginTag], "MIN PLAYERS REQUIRED FOR PLAY", i, g_iConfig[irequiredPlayers]);
		}

		g_bCheckPlayers = true;

		Call_StartForward(g_hOnRoundStartFailed);
		Call_PushCell(aPlayers.Length);
		Call_PushCell(g_iConfig[irequiredPlayers]);
		Call_Finish();

		GiveWeaponsOnFailStart();

		return;
	}

	g_bRoundStarted = true;
	g_bSelection = true;
	g_bCheckPlayers = false;

	int iTCount = GetTCount(aPlayers.Length);
	int iDCount = GetDCount(aPlayers.Length);

	int iTraitors;
	int iDetectives;
	int iInnocents;
	int iRand;
	int client;
	int iIndex;

	int counter = 0;
	int iCurrentTime = GetTime();

	while (iTraitors < iTCount)
	{
		if (g_aForceTraitor.Length > 0)
		{
			client = GetClientOfUserId(g_aForceTraitor.Get(0));
			
			if (client > 0)
			{
				iIndex = aPlayers.FindValue(client);
				
				if (iIndex != -1)
				{
					g_iRole[client] = TTT_TEAM_TRAITOR;
					iTraitors++;
					g_iLastRole[client] = TTT_TEAM_TRAITOR;
					aPlayers.Erase(iIndex);
				}
			}
			
			g_aForceTraitor.Erase(0);
			continue;
		}

		SetRandomSeed(iCurrentTime*100*counter++);
		iRand = GetRandomInt(0, aPlayers.Length - 1);
		client = aPlayers.Get(iRand);

		if (TTT_IsClientValid(client) && (g_iLastRole[client] != TTT_TEAM_TRAITOR || GetRandomInt(1, 3) == 2))
		{
			g_iRole[client] = TTT_TEAM_TRAITOR;
			g_iLastRole[client] = TTT_TEAM_TRAITOR;
			aPlayers.Erase(iRand);
			iTraitors++;
		}
	}

	while (iDetectives < iDCount && aPlayers.Length > 0)
	{
		if (g_aForceDetective.Length > 0)
		{
			client = GetClientOfUserId(g_aForceDetective.Get(0));
			
			if (client > 0)
			{
				iIndex = aPlayers.FindValue(client);
				
				if (iIndex != -1)
				{
					g_iLastRole[client] = TTT_TEAM_DETECTIVE;
					g_iRole[client] = TTT_TEAM_DETECTIVE;
					iDetectives++;
					aPlayers.Erase(iIndex);
				}
			}
			
			g_aForceDetective.Erase(0);
			continue;
		}

		if (aPlayers.Length <= (iDCount - iDetectives))
		{
			for (int i = 0; i < aPlayers.Length; i++)
			{
				g_iRole[aPlayers.Get(i)] = TTT_TEAM_DETECTIVE;
				g_iLastRole[client] = TTT_TEAM_DETECTIVE;
				iDetectives++;
			}
			break;
		}

		SetRandomSeed(iCurrentTime*100*counter++);
		iRand = GetRandomInt(0, aPlayers.Length - 1);
		client = aPlayers.Get(iRand);

		if (TTT_IsClientValid(client) && ((TTT_GetClientKarma(client) > g_iConfig[iminKarmaDetective] && g_iLastRole[client] == TTT_TEAM_INNOCENT) || GetRandomInt(1,3) == 2))
		{
			if (g_bAvoidDetective[client] == true)
			{
				g_iLastRole[client] = TTT_TEAM_INNOCENT;
				g_iRole[client] = TTT_TEAM_INNOCENT;
			}
			else
			{
				g_iLastRole[client] = TTT_TEAM_DETECTIVE;
				g_iRole[client] = TTT_TEAM_DETECTIVE;
				iDetectives++;
			}
			aPlayers.Erase(iRand);
		}
	}

	iInnocents = aPlayers.Length;

	while (aPlayers.Length > 0)
	{
		client = aPlayers.Get(0);
		if (TTT_IsClientValid(client))
		{
			g_iLastRole[client] = TTT_TEAM_INNOCENT;
			g_iRole[client] = TTT_TEAM_INNOCENT;
		}
		aPlayers.Erase(0);
	}

	delete aPlayers;


	LoopValidClients(i)
	{
		if ((!g_iConfig[bpublicKarma]) && g_iConfig[bkarmaRound])
		{
			g_iKarmaStart[i] = g_iKarma[i];
			CPrintToChat(i, g_iConfig[spluginTag], "All karma has been updated", i);
		}

		CPrintToChat(i, g_iConfig[spluginTag], "TEAMS HAS BEEN SELECTED", i);

		if (g_iRole[i] != TTT_TEAM_TRAITOR)
		{
			CPrintToChat(i, g_iConfig[spluginTag], "TRAITORS HAS BEEN SELECTED", i, iTraitors);
		}
		else
		{
			if (g_iConfig[bShowTraitors])
			{
				CPrintToChat(i, g_iConfig[spluginTag], "Your Traitor Partners", i);
				int iCount = 0;
			
				LoopValidClients(j)
				{
					if (!IsPlayerAlive(j) || i == j || g_iRole[j] != TTT_TEAM_TRAITOR)
					{
						continue;
					}
					CPrintToChat(i, g_iConfig[spluginTag], "Traitor List", i, j);
					iCount++;
				}
			
				if (iCount == 0)
				{
					CPrintToChat(i, g_iConfig[spluginTag], "No Traitor Partners", i);
				}
			}
		}

		if (GetClientTeam(i) != CS_TEAM_CT && GetClientTeam(i) != CS_TEAM_T)
		{
			continue;
		}

		if (!IsPlayerAlive(i))
		{
			continue;
		}

		if (!g_bDebug && IsFakeClient(i))
		{
			continue;
		}

		TeamInitialize(i);
	}

	if (g_aLogs != null)
	{
		g_aLogs.Clear();
	}

	g_iTeamSelectTime = GetTime();
	
	g_bSelection = false;

	Call_StartForward(g_hOnRoundStart);
	Call_PushCell(iInnocents);
	Call_PushCell(iTraitors);
	Call_PushCell(iDetectives);
	Call_Finish();
}

int GetTCount(int iActivePlayers)
{
	int iTCount = RoundToFloor(float(iActivePlayers) * (float(g_iConfig[itraitorRatio]) / 100.0));

	if (iTCount < 1)
	{
		iTCount = 1;
	}

	if (iTCount > g_iConfig[imaxTraitors])
	{
		iTCount = g_iConfig[imaxTraitors];
	}

	return iTCount;
}

int GetDCount(int iActivePlayers)
{
	if (iActivePlayers < g_iConfig[irequiredPlayersD])
	{
		return 0;
	}

	int iDCount = RoundToFloor(float(iActivePlayers) * (float(g_iConfig[idetectiveRatio]) / 100.0));

	if (iDCount > g_iConfig[imaxDetectives])
	{
		iDCount = g_iConfig[imaxDetectives];
	}

	return iDCount;
}


stock int GetRandomArray(Handle array)
{
	int size = GetArraySize(array);
	if (size == 0)
	{
		return -1;
	}

	return GetRandomInt(0, size - 1);
}

stock bool IsPlayerInArray(int player, Handle array)
{
	for (int i = 0; i < GetArraySize(array); i++)
	{
		if (player == GetArrayCell(array, i))
		{
			return true;
		}
	}

	return false;
}

stock void TeamInitialize(int client)
{
	if (!TTT_IsClientValid(client))
	{
		return;
	}
	
	g_bFound[client] = false;

	if (g_iRole[client] == TTT_TEAM_DETECTIVE)
	{
		if (g_iConfig[bforceTeams])
		{
			if (GetClientTeam(client) != CS_TEAM_CT)
			{
				CS_SwitchTeam(client, CS_TEAM_CT);
			}
		}

		if (GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY) == -1)
		{
			GivePlayerItem(client, g_iConfig[sdefaultPriD]);
		}

		CPrintToChat(client, g_iConfig[spluginTag], "Your Team is DETECTIVES", client);

		if (g_iConfig[ispawnHPD] > 0)
		{
			SetEntityHealth(client, g_iConfig[ispawnHPD]);
		}

		if (GetPlayerWeaponSlot(client, CS_SLOT_KNIFE) == -1)
		{
			GivePlayerItem(client, "weapon_knife");
		}

		if (GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY) == -1)
		{
			GivePlayerItem(client, g_iConfig[sdefaultSec]);
		}
	}
	else if (g_iRole[client] == TTT_TEAM_TRAITOR)
	{
		CPrintToChat(client, g_iConfig[spluginTag], "Your Team is TRAITORS", client);

		if (g_iConfig[ispawnHPT] > 0)
		{
			SetEntityHealth(client, g_iConfig[ispawnHPT]);
		}

		if (g_iConfig[bforceTeams])
		{
			if (GetClientTeam(client) != CS_TEAM_T)
			{
				CS_SwitchTeam(client, CS_TEAM_T);
			}
		}
		if (GetPlayerWeaponSlot(client, CS_SLOT_KNIFE) == -1)
		{
			GivePlayerItem(client, "weapon_knife");
		}

		if (GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY) == -1)
		{
			GivePlayerItem(client, g_iConfig[sdefaultSec]);
		}
	}
	else if (g_iRole[client] == TTT_TEAM_INNOCENT)
	{
		CPrintToChat(client, g_iConfig[spluginTag], "Your Team is INNOCENTS", client);

		if (g_iConfig[ispawnHPI] > 0)
		{
			SetEntityHealth(client, g_iConfig[ispawnHPI]);
		}

		if (g_iConfig[bforceTeams])
		{
			if (GetClientTeam(client) != CS_TEAM_T)
			{
				CS_SwitchTeam(client, CS_TEAM_T);
			}
		}
		if (GetPlayerWeaponSlot(client, CS_SLOT_KNIFE) == -1)
		{
			GivePlayerItem(client, "weapon_knife");
		}

		if (GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY) == -1)
		{
			GivePlayerItem(client, g_iConfig[sdefaultSec]);
		}
	}

	CheckClantag(client);

	if (g_iConfig[bupdateClientModel])
	{
		CS_UpdateClientModel(client);
	}
	else if (g_iConfig[bforceModel])
	{
		switch (g_iRole[client])
		{
			case TTT_TEAM_INNOCENT, TTT_TEAM_TRAITOR:
			{
				SetEntityModel(client, g_iConfig[smodelT]);
			}
			case TTT_TEAM_DETECTIVE:
			{
				SetEntityModel(client, g_iConfig[smodelCT]);
			}
		}
	}

	Call_StartForward(g_hOnClientGetRole);
	Call_PushCell(client);
	Call_PushCell(g_iRole[client]);
	Call_Finish();
}

stock void TeamTag(int client)
{
	if (!TTT_IsClientValid(client))
	{
		return;
	}

	if (g_iRole[client] == TTT_TEAM_DETECTIVE)
	{
		CS_SetClientClanTag(client, "DETECTIVE");
	}
	else if (g_iRole[client] == TTT_TEAM_TRAITOR)
	{
		CS_SetClientClanTag(client, "TRAITOR");
	}
	else if (g_iRole[client] == TTT_TEAM_INNOCENT)
	{
		CS_SetClientClanTag(client, "INNOCENT");
	}
	else if (g_iRole[client] == TTT_TEAM_UNASSIGNED)
	{
		CS_SetClientClanTag(client, "UNASSIGNED");
	}
	else
	{
		CS_SetClientClanTag(client, " ");
	}
}

public Action Event_PlayerSpawn_Pre(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (g_bRoundStarted && TTT_IsClientValid(client))
	{
		CS_SetClientClanTag(client, "UNASSIGNED");
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (TTT_IsClientValid(client))
	{
		if (g_bRoundStarted)
		{
			if (g_iConfig[bslayAfterStart])
			{
				g_iRole[client] = TTT_TEAM_UNASSIGNED;
				RequestFrame(Frame_SlapPlayer, GetClientUserId(client));
				CS_SetClientClanTag(client, "UNASSIGNED");
			}
		}
		else
		{
			CS_SetClientClanTag(client, " ");

			if (g_iConfig[bEnableDamage])
			{
				GivePlayerItem(client, "weapon_knife");

				char sWeapon[32];
				Format(sWeapon, sizeof(sWeapon), "weapon_%s", g_iConfig[sFSSecondary]);
				GivePlayerItem(client, sWeapon);

				Format(sWeapon, sizeof(sWeapon), "weapon_%s", g_iConfig[sFSPrimary]);
				GivePlayerItem(client, sWeapon);
			}
		}

		g_iInnoKills[client] = 0;
		g_iTraitorKills[client] = 0;
		g_iDetectiveKills[client] = 0;

		StripAllWeapons(client);

		if (g_bInactive)
		{
			int iCount = 0;

			LoopValidClients(i)
			{
				if (IsPlayerAlive(i) && (GetClientTeam(i) > CS_TEAM_SPECTATOR))
				{
					iCount++;
				}
			}

			if (iCount >= 3)
			{
				ServerCommand("mp_restartgame 2");
			}
		}

		if (!g_bInactive && g_iConfig[bshowKarmaOnSpawn])
		{
			CPrintToChat(client, g_iConfig[spluginTag], "Your karma is", client, g_iKarma[client]);
		}

		if (g_iConfig[benableNoBlock])
		{
			SetNoBlock(client);
		}

		if (g_iConfig[bTranfserArmor] && g_iArmor[client] > 0)
		{
			SetEntProp(client, Prop_Send, "m_ArmorValue", g_iArmor[client]);
			g_iArmor[client] = 0;
		}
	}
}

public void Frame_SlapPlayer(any userid)
{
	int client = GetClientOfUserId(userid);

	if (TTT_IsClientValid(client) && IsPlayerAlive(client))
	{
		ForcePlayerSuicide(client);
	}
}

public Action UserMessage_TextMsg(UserMsg msg_id, Protobuf msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if (g_iConfig[bHideTeamAttackMessage] && reliable)
	{
		char sMessage[MAX_MESSAGE_LENGTH];
		
		msg.ReadString("params", sMessage, sizeof(sMessage), 0);
		
		if (StrContains(sMessage, "teamate_attack") != -1)
		{
			return Plugin_Handled;
		}
	}
	
	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	HookClient(client);
}

void LateLoadClients(bool bHook = false)
{
	LoopValidClients(i)
	{
		LoadClientKarma(GetClientUserId(i));

		if (bHook)
		{
			HookClient(i);
		}
	}
}

void HookClient(int client)
{
	SDKHook(client, SDKHook_TraceAttack, OnTraceAttack);
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
	SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponPostSwitch);
	SDKHook(client, SDKHook_PostThink, OnPostThink);
}

public Action OnPostThink(int client)
{
	if (TTT_IsClientValid(client))
	{
		int iKarma;
		if (g_iConfig[bpublicKarma])
		{
			if (g_bFound[client])
			{
				iKarma = g_iKarma[client] * -1;
			}
			else
			{
				iKarma = g_iKarma[client];
			}
		}
		else if (g_iConfig[bkarmaRound])
		{
			if (g_bFound[client])
			{
				iKarma = g_iKarmaStart[client] * -1;
			}
			else
			{
				iKarma = g_iKarmaStart[client];
			}
		}
		CS_SetClientContributionScore(client, iKarma);
	}
}

stock void BanBadPlayerKarma(int client)
{
	char sReason[512];
	Format(sReason, sizeof(sReason), "%T", "Your Karma is too low", client);

	setKarma(client, g_iConfig[istartKarma], true);

	if (g_bSourcebans)
	{
		SBBanPlayer(0, client, g_iConfig[ikarmaBanLength], sReason);
	}
	else
	{
		ServerCommand("sm_ban #%d %d \"%s\"", GetClientUserId(client), g_iConfig[ikarmaBanLength], sReason);
	}
}

public Action OnTraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
	if (IsDamageForbidden())
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action OnTakeDamageAlive(int iVictim, int &iAttacker, int &inflictor, float &damage, int &damagetype)
{
	if (IsDamageForbidden())
	{
		return Plugin_Handled;
	}

	if (g_bRoundStarted && !g_bRoundEnded)
	{
		if (TTT_IsClientValid(iAttacker) && iAttacker != iVictim && g_iConfig[bkarmaDMG])
		{
			if (g_iConfig[bkarmaDMG_up] || (g_iKarma[iAttacker] < g_iConfig[istartKarma]))
			{
				damage *= FloatDiv(float(g_iKarma[iAttacker]), float(g_iConfig[istartKarma]));
				return Plugin_Changed;
			}
		}
	}

	return Plugin_Continue;
}

bool IsDamageForbidden()
{
	if (g_bRoundEnded && !g_iConfig[broundendDamage])
	{
		return true;
	}
	
	if (!g_bRoundStarted && !g_iConfig[bEnableDamage])
	{
		return true;
	}

	return false;
}

public Action Event_PlayerDeathPre(Event event, const char[] menu, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	g_iInnoKills[client] = 0;
	g_iTraitorKills[client] = 0;
	g_iDetectiveKills[client] = 0;

	int iRagdoll = 0;
	if (g_iRole[client] > TTT_TEAM_UNASSIGNED)
	{
		iRagdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
		if (iRagdoll > 0)
		{
			AcceptEntityInput(iRagdoll, "Kill");
		}

		char playermodel[128];
		GetClientModel(client, playermodel, 128);

		float origin[3], angles[3], velocity[3];

		GetClientAbsOrigin(client, origin);
		GetClientAbsAngles(client, angles);
		GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);

		int iEntity = CreateEntityByName("prop_ragdoll");
		DispatchKeyValue(iEntity, "model", playermodel);
		SetEntProp(iEntity, Prop_Data, "m_nSolidType", 6);
		SetEntProp(iEntity, Prop_Data, "m_CollisionGroup", 5);

		ActivateEntity(iEntity);
		if (DispatchSpawn(iEntity))
		{
			float speed = GetVectorLength(velocity);
			if (speed >= 500)
			{
				TeleportEntity(iEntity, origin, angles, NULL_VECTOR);
			}
			else
			{
				TeleportEntity(iEntity, origin, angles, velocity);
			}
		}
		else
		{
			LogToFileEx(g_iConfig[serrFile], "Unable to spawn ragdoll for %N (Auth: %i)", client, GetSteamAccountID(client));
		}

		SetEntProp(iEntity, Prop_Data, "m_CollisionGroup", 2);

		int iAttacker = GetClientOfUserId(event.GetInt("attacker"));
		char name[MAX_NAME_LENGTH];
		GetClientName(client, name, sizeof(name));
		int iRagdollC[Ragdolls];
		iRagdollC[Ent] = EntIndexToEntRef(iEntity);
		iRagdollC[Victim] = client;
		iRagdollC[VictimTeam] = g_iRole[client];
		Format(iRagdollC[VictimName], MAX_NAME_LENGTH, name);
		iRagdollC[Scanned] = false;
		GetClientName(iAttacker, name, sizeof(name));
		iRagdollC[Attacker] = iAttacker;
		iRagdollC[AttackerTeam] = g_iRole[iAttacker];
		Format(iRagdollC[AttackerName], MAX_NAME_LENGTH, name);
		iRagdollC[GameTime] = GetGameTime();
		event.GetString("weapon", iRagdollC[Weaponused], sizeof(iRagdollC[Weaponused]));

		g_aRagdoll.PushArray(iRagdollC[0]);

		SetEntPropEnt(client, Prop_Send, "m_hRagdoll", iEntity);

		if (client != iAttacker && iAttacker != 0 && !g_bImmuneRDMManager[iAttacker] && !g_bHoldingProp[client] && !g_bHoldingSilencedWep[client])
		{
			if (g_iRole[iAttacker] == TTT_TEAM_TRAITOR && g_iRole[client] == TTT_TEAM_TRAITOR)
			{
				if (g_hRDMTimer[client] != null)
				{
					KillTimer(g_hRDMTimer[client]);
				}

				g_hRDMTimer[client] = CreateTimer(3.0, Timer_RDMTimer, GetClientUserId(client));
				g_iRDMAttacker[client] = iAttacker;
			}
			else if (g_iRole[iAttacker] == TTT_TEAM_DETECTIVE && g_iRole[client] == TTT_TEAM_DETECTIVE)
			{
				if (g_hRDMTimer[client] != null)
				{
					KillTimer(g_hRDMTimer[client]);
				}

				g_hRDMTimer[client] = CreateTimer(3.0, Timer_RDMTimer, GetClientUserId(client));
				g_iRDMAttacker[client] = iAttacker;
			}
			else if (g_iRole[iAttacker] == TTT_TEAM_INNOCENT && g_iRole[client] == TTT_TEAM_DETECTIVE)
			{
				if (g_hRDMTimer[client] != null)
				{
					KillTimer(g_hRDMTimer[client]);
				}

				g_hRDMTimer[client] = CreateTimer(3.0, Timer_RDMTimer, GetClientUserId(client));
				g_iRDMAttacker[client] = iAttacker;
			}

			if ((g_iRole[iAttacker] == TTT_TEAM_INNOCENT && g_iRole[client] == TTT_TEAM_INNOCENT) || (g_iRole[iAttacker] == TTT_TEAM_INNOCENT && g_iRole[client] == TTT_TEAM_DETECTIVE))
			{
				g_iInnoKills[iAttacker]++;
			}
			else if (g_iRole[iAttacker] == TTT_TEAM_TRAITOR && g_iRole[client] == TTT_TEAM_TRAITOR)
			{
				g_iTraitorKills[iAttacker]++;
			}
			else if ((g_iRole[iAttacker] == TTT_TEAM_DETECTIVE && g_iRole[client] == TTT_TEAM_INNOCENT) || (g_iRole[iAttacker] == TTT_TEAM_DETECTIVE && g_iRole[client] == TTT_TEAM_DETECTIVE))
			{
				g_iDetectiveKills[iAttacker]++;
			}

			if (g_iInnoKills[iAttacker] >= g_iConfig[ipunishInnoKills])
			{
				ServerCommand("sm_slay #%i 5", GetClientUserId(iAttacker));
			}

			if (g_iTraitorKills[iAttacker] >= g_iConfig[ipunishTraitorKills])
			{
				ServerCommand("sm_slay #%i 5", GetClientUserId(iAttacker));
			}

			if (g_iDetectiveKills[iAttacker] >= g_iConfig[ipunishDetectiveKills])
			{
				ServerCommand("sm_slay #%i 5", GetClientUserId(iAttacker));
			}
		}
	}
	else
	{
		iRagdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
		if (iRagdoll > 0)
		{
			AcceptEntityInput(iRagdoll, "Kill");
		}
	}

	event.BroadcastDisabled = true;

	return Plugin_Handled;
}

public void OnClientPostAdminCheck(int client)
{
	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	nameCheck(client, name);

	g_bImmuneRDMManager[client] = false;
	g_bFound[client] = true;

	g_iRole[client] = TTT_TEAM_UNASSIGNED;
	CS_SetClientClanTag(client, "UNASSIGNED");

	if (TTT_GetSQLConnection() != null)
	{
		CreateTimer(1.0, Timer_OnClientPostAdminCheck, GetClientUserId(client));
	}

	if (g_iConfig[bshowRulesMenu])
	{
		CreateTimer(3.0, Timer_ShowWelcomeMenu, GetClientUserId(client));
	}
	else if (g_iConfig[bshowDetectiveMenu])
	{
		CreateTimer(3.0, Timer_ShowDetectiveMenu, GetClientUserId(client));
	}
}

public Action Timer_OnClientPostAdminCheck(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);

	if (TTT_IsClientValid(client))
	{
		LoadClientKarma(GetClientUserId(client));
	}
}

public Action Command_TRules(int client, int args)
{
	if (!g_iConfig[bshowRulesMenu])
	{
		return Plugin_Handled;
	}

	ShowRules(client, g_iSite[client]);
	return Plugin_Handled;
}

public Action Command_DetectiveRules(int client, int args)
{
	if (!g_iConfig[bshowDetectiveMenu])
	{
		return Plugin_Handled;
	}

	AskClientForMicrophone(client);
	return Plugin_Handled;
}

public void Frame_ShowWelcomeMenu(any userid)
{
	int client = GetClientOfUserId(userid);

	if (TTT_IsClientValid(client))
	{
		ShowRules(client, g_iSite[client]);
	}
}

public Action Timer_ShowWelcomeMenu(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);

	if (TTT_IsClientValid(client))
	{
		ShowRules(client, g_iSite[client]);
	}
}

stock void ShowRules(int client, int iItem)
{
	char sText[512], sYes[64];
	Format(sText, sizeof(sText), "%T", "Welcome Menu", client, client, TTT_PLUGIN_AUTHOR);
	Format(sYes, sizeof(sYes), "%T", "WM Yes", client);

	Menu menu = new Menu(Menu_ShowWelcomeMenu);
	menu.SetTitle(sText);

	Handle hFile = OpenFile(g_sRulesFile, "rt");

	if (hFile == null)
	{
		SetFailState("[TTT] Can't open File: %s", g_sRulesFile);
	}

	KeyValues kvRules = CreateKeyValues("Rules");

	if (!kvRules.ImportFromFile(g_sRulesFile))
	{
		SetFailState("Can't read %s correctly! (ImportFromFile)", g_sRulesFile);
		return;
	}

	if (!kvRules.GotoFirstSubKey())
	{
		SetFailState("Can't read %s correctly! (GotoFirstSubKey)", g_sRulesFile);
		return;
	}

	do
	{
		char sNumber[4];
		char sTitle[64];

		kvRules.GetSectionName(sNumber, sizeof(sNumber));
		kvRules.GetString("title", sTitle, sizeof(sTitle));
		menu.AddItem(sNumber, sTitle);
	}
	while (kvRules.GotoNextKey());

	delete kvRules;
	delete hFile;

	menu.AddItem("yes", sYes);
	menu.ExitButton = false;
	menu.ExitBackButton = false;
	menu.DisplayAt(client, iItem, g_iConfig[itimeToReadRules]);
}

public int Menu_ShowWelcomeMenu(Menu menu, MenuAction action, int client, int param)
{
	if (action == MenuAction_Select)
	{
		char sParam[32];
		GetMenuItem(menu, param, sParam, sizeof(sParam));

		if (!StrEqual(sParam, "yes", false))
		{
			Handle hFile = OpenFile(g_sRulesFile, "rt");

			if (hFile == null)
			{
				SetFailState("[TTT] Can't open File: %s", g_sRulesFile);
				return 0;
			}

			KeyValues kvRules = CreateKeyValues("Rules");

			if (!kvRules.ImportFromFile(g_sRulesFile))
			{
				SetFailState("Can't read %s correctly! (ImportFromFile)", g_sRulesFile);
				delete kvRules;
				return 0;
			}


			if (kvRules.JumpToKey(sParam, false))
			{
				char sValue[MAX_MESSAGE_LENGTH];

				kvRules.GetString("text", sValue, sizeof(sValue));
				if (strlen(sValue) > 0)
				{
					CPrintToChat(client, sValue);
					RequestFrame(Frame_ShowWelcomeMenu, GetClientUserId(client));

					g_bKnowRules[client] = false;
					g_bReadRules[client] = true;

					delete kvRules;
					return 0;
				}

				kvRules.GetString("fakecommand", sValue, sizeof(sValue));
				if (strlen(sValue) > 0)
				{
					FakeClientCommand(client, sValue);

					g_bKnowRules[client] = false;
					g_bReadRules[client] = true;

					delete kvRules;
					return 0;
				}

				kvRules.GetString("command", sValue, sizeof(sValue));
				if (strlen(sValue) > 0)
				{
					ClientCommand(client, sValue);

					g_bKnowRules[client] = false;
					g_bReadRules[client] = true;

					delete kvRules;
					return 0;
				}

				kvRules.GetString("url", sValue, sizeof(sValue));
				if (strlen(sValue) > 0)
				{
					char sURL[512];
					Format(sURL, sizeof(sURL), "http://cola-team.com/franug/webshortcuts2.php?web=height=720,width=1280;franug_is_pro;%s", sValue); // TODO: Replace this
					ShowMOTDPanel(client, "TTT Rules", sURL, MOTDPANEL_TYPE_URL);

					g_bKnowRules[client] = false;
					g_bReadRules[client] = true;

					delete kvRules;
					return 0;
				}

				kvRules.GetString("file", sValue, sizeof(sValue));
				if (strlen(sValue) > 0)
				{
					g_iSite[client] = menu.Selection;

					char sFile[PLATFORM_MAX_PATH + 1];
					BuildPath(Path_SM, sFile, sizeof(sFile), "configs/ttt/rules/%s", sValue);

					Handle hRFile = OpenFile(sFile, "rt");

					if (hRFile == null)
					SetFailState("[TTT] Can't open File: %s", sFile);

					char sLine[64], sTitle[64];

					Menu rMenu = new Menu(Menu_RulesPage);

					kvRules.GetString("title", sTitle, sizeof(sTitle));
					rMenu.SetTitle(sTitle);

					while (!IsEndOfFile(hRFile) && ReadFileLine(hRFile, sLine, sizeof(sLine)))
					{
						if (strlen(sLine) > 1)
						{
							rMenu.AddItem("", sLine, ITEMDRAW_DISABLED);
						}
					}

					rMenu.ExitButton = false;
					rMenu.ExitBackButton = true;
					rMenu.Display(client, g_iConfig[itimeToReadRules]);

					delete hRFile;
					delete kvRules;

					return 0;
				}

				delete kvRules;

				return 0;
			}
			
			delete hFile;
		}
		else
		{
			g_bKnowRules[client] = true;
			g_bReadRules[client] = false;
		}

		if (g_iConfig[bshowDetectiveMenu])
		{
			AskClientForMicrophone(client);
		}
	}
	else if (action == MenuAction_Cancel)
	{
		if (TTT_IsClientValid(client) && g_iConfig[irulesClosePunishment] == 0)
		{
			if (!TTT_HasFlags(client, g_iConfig[slogsAccess]))
			{
				char sMessage[128];
				Format(sMessage, sizeof(sMessage), "%T", "WM Kick Message", client);
				KickClient(client, sMessage);
			}
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int Menu_RulesPage(Menu menu, MenuAction action, int client, int param)
{
	if (action == MenuAction_Cancel || action == MenuAction_Select || param == MenuCancel_ExitBack)
	{
		ShowRules(client, 0);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}

public Action Timer_ShowDetectiveMenu(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);

	if (TTT_IsClientValid(client))
	{
		AskClientForMicrophone(client);
	}
}

stock void AskClientForMicrophone(int client)
{
	char sText[512], sYes[64], sNo[64];
	Format(sText, sizeof(sText), "%T", "AM Question", client);
	Format(sYes, sizeof(sYes), "%T", "AM Yes", client);
	Format(sNo, sizeof(sNo), "%T", "AM No", client);

	Menu menu = new Menu(Menu_AskClientForMicrophone);
	menu.SetTitle(sText);
	menu.AddItem("no", sNo);
	menu.AddItem("yes", sYes);
	menu.ExitButton = false;
	menu.ExitBackButton = false;
	menu.Display(client, g_iConfig[itimeToReadDetectiveRules]);
}


public int Menu_AskClientForMicrophone(Menu menu, MenuAction action, int client, int param)
{
	if (action == MenuAction_Select)
	{
		char sParam[32];
		GetMenuItem(menu, param, sParam, sizeof(sParam));

		if (!StrEqual(sParam, "yes", false))
		{
			g_bAvoidDetective[client] = true;
		}
		else
		{
			g_bAvoidDetective[client] = false;
		}
	}
	else if (action == MenuAction_Cancel)
	{
		g_bAvoidDetective[client] = true;
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void OnClientDisconnect(int client)
{
	if (IsClientInGame(client))
	{
		g_bKarma[client] = false;
		g_bFound[client] = true;


		if (g_iConfig[bTranfserArmor])
		{
			g_iArmor[client] = 0;
		}

		ClearTimer(g_hRDMTimer[client]);

		g_bReceivingLogs[client] = false;
		g_bImmuneRDMManager[client] = false;
	}
}

public Action Event_ChangeName(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (!IsClientInGame(client))
	{
		return;
	}

	char userName[MAX_NAME_LENGTH];
	event.GetString("newname", userName, sizeof(userName));
	nameCheck(client, userName);

	int iSize = g_aRagdoll.Length;

	if (iSize == 0)
	{
		return;
	}

	int iRagdollC[Ragdolls];

	//TODO Make this based on the userid to prevent abuse
	for (int i = 0; i < g_aRagdoll.Length; i++)
	{
		g_aRagdoll.GetArray(i, iRagdollC[0]);

		if (client == iRagdollC[Attacker])
		{
			Format(iRagdollC[AttackerName], MAX_NAME_LENGTH, userName);
			g_aRagdoll.SetArray(i, iRagdollC[0]);
		}
		else if (client == iRagdollC[Victim])
		{
			Format(iRagdollC[VictimName], MAX_NAME_LENGTH, userName);
			g_aRagdoll.SetArray(i, iRagdollC[0]);
		}
	}
}

public Action Timer_1(Handle timer)
{
	int g_iInnoAlive = 0;
	int g_iTraitorAlive = 0;
	int g_iDetectiveAlive = 0;

	float vec[3];
	LoopValidClients(i)
	{
		Call_StartForward(g_hOnUpdate1);
		Call_PushCell(i);
		Call_Finish();

		if (IsPlayerAlive(i))
		{
			if (g_iRole[i] == TTT_TEAM_TRAITOR)
			{
				g_iTraitorAlive++;
				int[] clients = new int[MaxClients];
				int index = 0;

				LoopValidClients(j)
				{
					if (IsPlayerAlive(j) && j != i && (g_iRole[j] == TTT_TEAM_TRAITOR))
					{
						clients[index] = j;
						index++;
					}
				}

				GetClientAbsOrigin(i, vec);
				vec[2] += 10;

				TE_SetupBeamRingPoint(vec, 50.0, 60.0, g_iBeamSprite, g_iHaloSprite, 0, 15, 0.1, 10.0, 0.0, { 0, 0, 255, 255 }, 10, 0);
				TE_Send(clients, index);
			}
			else if (g_iRole[i] == TTT_TEAM_INNOCENT)
			{
				g_iInnoAlive++;
			}
			else if (g_iRole[i] == TTT_TEAM_DETECTIVE)
			{
				g_iDetectiveAlive++;
			}
		}
	}

	if (g_bRoundStarted)
	{
		if (g_iInnoAlive == 0 && ((g_iConfig[bendwithD]) || (g_iDetectiveAlive == 0)))
		{
			g_bRoundStarted = false;

			if (!g_bDebug)
			{
				CS_TerminateRound(7.0, CSRoundEnd_TerroristWin);
			}
		}
		else if (g_iTraitorAlive == 0)
		{
			g_bRoundStarted = false;

			if (!g_bDebug)
			{
				CS_TerminateRound(7.0, CSRoundEnd_CTWin);
			}
		}
	}
}


public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (!TTT_IsClientValid(client))
	{
		return;
	}

	int iAttacker = GetClientOfUserId(event.GetInt("attacker"));
	if (!TTT_IsClientValid(iAttacker) || iAttacker == client)
	{
		return;
	}

	if (g_iConfig[bshowDeathMessage])
	{
		if (g_iRole[iAttacker] == TTT_TEAM_TRAITOR)
		{
			CPrintToChat(client, g_iConfig[spluginTag], "Your killer is a Traitor", client);
		}
		else if (g_iRole[iAttacker] == TTT_TEAM_DETECTIVE)
		{
			CPrintToChat(client, g_iConfig[spluginTag], "Your killer is a Detective", client);
		}
		else if (g_iRole[iAttacker] == TTT_TEAM_INNOCENT)
		{
			CPrintToChat(client, g_iConfig[spluginTag], "Your killer is an Innocent", client);
		}
	}

	if (g_iConfig[bshowKillMessage])
	{
		if (g_iRole[client] == TTT_TEAM_TRAITOR)
		{
			CPrintToChat(iAttacker, g_iConfig[spluginTag], "You killed a Traitor", iAttacker);
		}
		else if (g_iRole[client] == TTT_TEAM_DETECTIVE)
		{
			CPrintToChat(iAttacker, g_iConfig[spluginTag], "You killed a Detective", iAttacker);
		}
		else if (g_iRole[client] == TTT_TEAM_INNOCENT)
		{
			CPrintToChat(iAttacker, g_iConfig[spluginTag], "You killed an Innocent", iAttacker);
		}
	}

	char iItem[TTT_ITEM_SIZE];
	char sWeapon[32];
	event.GetString("weapon", sWeapon, sizeof(sWeapon));
	
	char sAttackerID[32], sClientID[32];
	
	if (g_iConfig[bAddSteamIDtoLogs])
	{
		if (g_iConfig[iSteamIDLogFormat] == 1)
		{
			GetClientAuthId(iAttacker, AuthId_Steam2, sAttackerID, sizeof(sAttackerID));
			GetClientAuthId(client, AuthId_Steam2, sClientID, sizeof(sClientID));
		}
		else if (g_iConfig[iSteamIDLogFormat] == 2)
		{
			GetClientAuthId(iAttacker, AuthId_Steam3, sAttackerID, sizeof(sAttackerID));
			GetClientAuthId(client, AuthId_Steam3, sClientID, sizeof(sClientID));
		}
		else if (g_iConfig[iSteamIDLogFormat] == 3)
		{
			GetClientAuthId(iAttacker, AuthId_SteamID64, sAttackerID, sizeof(sAttackerID));
			GetClientAuthId(client, AuthId_SteamID64, sClientID, sizeof(sClientID));
		}
		
		if (strlen(sAttackerID) > 2 && strlen(sClientID) > 2)
		{
			Format(sAttackerID, sizeof(sAttackerID), " (%s)", sAttackerID);
			Format(sClientID, sizeof(sClientID), " (%s)", sClientID);
		}
	}

	if (g_iRole[iAttacker] == TTT_TEAM_INNOCENT && g_iRole[client] == TTT_TEAM_INNOCENT)
	{
		Format(iItem, sizeof(iItem), "-> [%N%s (Innocent) killed %N%s (Innocent) with %s] - BAD ACTION", iAttacker, sAttackerID, client, sClientID, sWeapon);
		addArrayTime(iItem);

		subtractKarma(iAttacker, g_iConfig[ikarmaII], true);
	}
	else if (g_iRole[iAttacker] == TTT_TEAM_INNOCENT && g_iRole[client] == TTT_TEAM_TRAITOR)
	{
		Format(iItem, sizeof(iItem), "-> [%N%s (Innocent) killed %N%s (Traitor) with %s]", iAttacker, sAttackerID, client, sClientID, sWeapon);
		addArrayTime(iItem);

		addKarma(iAttacker, g_iConfig[ikarmaIT], true);
	}
	else if (g_iRole[iAttacker] == TTT_TEAM_INNOCENT && g_iRole[client] == TTT_TEAM_DETECTIVE)
	{
		Format(iItem, sizeof(iItem), "-> [%N%s (Innocent) killed %N%s (Detective) with %s] - BAD ACTION", iAttacker, sAttackerID, client, sClientID, sWeapon);
		addArrayTime(iItem);

		subtractKarma(iAttacker, g_iConfig[ikarmaID], true);
	}
	else if (g_iRole[iAttacker] == TTT_TEAM_TRAITOR && g_iRole[client] == TTT_TEAM_INNOCENT)
	{
		Format(iItem, sizeof(iItem), "-> [%N%s (Traitor) killed %N%s (Innocent) with %s]", iAttacker, sAttackerID, client, sClientID, sWeapon);
		addArrayTime(iItem);

		addKarma(iAttacker, g_iConfig[ikarmaTI], true);
	}
	else if (g_iRole[iAttacker] == TTT_TEAM_TRAITOR && g_iRole[client] == TTT_TEAM_TRAITOR)
	{
		Format(iItem, sizeof(iItem), "-> [%N%s (Traitor) killed %N%s (Traitor) with %s] - BAD ACTION", iAttacker, sAttackerID, client, sClientID, sWeapon);
		addArrayTime(iItem);

		subtractKarma(iAttacker, g_iConfig[ikarmaTT], true);
	}
	else if (g_iRole[iAttacker] == TTT_TEAM_TRAITOR && g_iRole[client] == TTT_TEAM_DETECTIVE)
	{
		Format(iItem, sizeof(iItem), "-> [%N%s (Traitor) killed %N%s (Detective) with %s]", iAttacker, sAttackerID, client, sClientID, sWeapon);
		addArrayTime(iItem);

		addKarma(iAttacker, g_iConfig[ikarmaTD], true);
	}
	else if (g_iRole[iAttacker] == TTT_TEAM_DETECTIVE && g_iRole[client] == TTT_TEAM_INNOCENT)
	{
		Format(iItem, sizeof(iItem), "-> [%N%s (Detective) killed %N%s (Innocent) with %s] - BAD ACTION", iAttacker, sAttackerID, client, sClientID, sWeapon);
		addArrayTime(iItem);

		subtractKarma(iAttacker, g_iConfig[ikarmaDI], true);
	}
	else if (g_iRole[iAttacker] == TTT_TEAM_DETECTIVE && g_iRole[client] == TTT_TEAM_TRAITOR)
	{
		Format(iItem, sizeof(iItem), "-> [%N%s (Detective) killed %N%s (Traitor) with %s]", iAttacker, sAttackerID, client, sClientID, sWeapon);
		addArrayTime(iItem);

		addKarma(iAttacker, g_iConfig[ikarmaDT], true);
	}
	else if (g_iRole[iAttacker] == TTT_TEAM_DETECTIVE && g_iRole[client] == TTT_TEAM_DETECTIVE)
	{
		Format(iItem, sizeof(iItem), "-> [%N%s (Detective) killed %N%s (Detective) with %s] - BAD ACTION", iAttacker, sAttackerID, client, sClientID, sWeapon);
		addArrayTime(iItem);

		subtractKarma(iAttacker, g_iConfig[ikarmaDD], true);
	}

	if (g_iRole[client] == TTT_TEAM_UNASSIGNED)
	{
		CS_SetClientClanTag(client, "UNASSIGNED");
		g_bFound[client] = true;
	}

	CheckTeams();

	Call_StartForward(g_hOnClientDeath);
	Call_PushCell(client);
	Call_PushCell(iAttacker);
	Call_Finish();
}

public void OnMapEnd()
{
	g_bRoundEnding = false;
	if (g_hRoundTimer != null)
	{
		delete g_hRoundTimer;
		g_hRoundTimer = null;
	}

	g_hStartTimer = null;
	g_hCountdownTimer = null;

	LoopValidClients(i)
	{
		if (g_iConfig[bTranfserArmor])
			g_iArmor[i] = 0;
		g_bKarma[i] = false;
	}
}

public Action Timer_OnRoundEnd(Handle timer)
{
	g_hRoundTimer = null;
	g_bRoundStarted = false;

	if (!g_bDebug)
	{
		CS_TerminateRound(7.0, CSRoundEnd_CTWin);
	}
}

public Action CS_OnTerminateRound(float &delay, CSRoundEndReason &reason)
{
	if (g_bRoundStarted)
	{
		return Plugin_Handled;
	}

	bool bInnoAlive = false;
	bool bDeteAlive = false;

	int WinningTeam = TTT_TEAM_UNASSIGNED;

	LoopValidClients(client)
	{
		if ((!g_iConfig[bpublicKarma]) && g_iConfig[bkarmaRound])
		{
			g_iKarmaStart[client] = g_iKarma[client];
			CPrintToChat(client, g_iConfig[spluginTag], "All karma has been updated", client);
		}

		if (IsPlayerAlive(client))
		{
			if (g_iRole[client] == TTT_TEAM_INNOCENT)
			{
				bInnoAlive = true;
			}
			else if (g_iRole[client] == TTT_TEAM_DETECTIVE)
			{
				bDeteAlive = true;
			}
		}
	}

	if (bInnoAlive)
	{
		WinningTeam = TTT_TEAM_INNOCENT;
	}
	else if (!bInnoAlive && bDeteAlive)
	{
		if (g_iConfig[bendwithD])
		{
			WinningTeam = TTT_TEAM_DETECTIVE;
		}
		else
		{
			WinningTeam = TTT_TEAM_INNOCENT;
		}
	}
	else
	{
		WinningTeam = TTT_TEAM_TRAITOR;
	}

	Call_StartForward(g_hOnRoundEnd);
	Call_PushCell(WinningTeam);
	Call_Finish();

	if (g_iConfig[brandomWinner])
	{
		reason = view_as<CSRoundEndReason>(GetRandomInt(view_as<int>(CSRoundEnd_CTWin), view_as<int>(CSRoundEnd_TerroristWin)));
	}

	if (g_iConfig[f_roundDelay] > 0.0)
	{
		delay = g_iConfig[f_roundDelay];
	}

	if (g_iConfig[bnextRoundAlert])
	{
		LoopValidClients(client)
		{
			CPrintToChat(client, g_iConfig[spluginTag], "next round in", client, delay);
		}
	}

	g_bRoundEnding = true;

	return Plugin_Changed;
}

public Action Event_PlayerTeam_Pre(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (!g_bSelection)
	{
		CheckClantag(client);
	}

	if (g_iConfig[bhideTeams] && (!event.GetBool("silent")))
	{
		event.BroadcastDisabled = true;
		dontBroadcast = true;
	}

	return Plugin_Changed;
}

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int iAttacker = GetClientOfUserId(event.GetInt("attacker"));
	if (!iAttacker)
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));


	int damage = event.GetInt("dmg_health");

	char iItem[TTT_ITEM_SIZE];
	char sWeapon[32];
	event.GetString("weapon", sWeapon, sizeof(sWeapon));
	
	char sAttackerID[32], sClientID[32];
	
	if (g_iConfig[bAddSteamIDtoLogs])
	{
		if (g_iConfig[iSteamIDLogFormat] == 1)
		{
			GetClientAuthId(iAttacker, AuthId_Steam2, sAttackerID, sizeof(sAttackerID));
			GetClientAuthId(client, AuthId_Steam2, sClientID, sizeof(sClientID));
		}
		else if (g_iConfig[iSteamIDLogFormat] == 2)
		{
			GetClientAuthId(iAttacker, AuthId_Steam3, sAttackerID, sizeof(sAttackerID));
			GetClientAuthId(client, AuthId_Steam3, sClientID, sizeof(sClientID));
		}
		else if (g_iConfig[iSteamIDLogFormat] == 3)
		{
			GetClientAuthId(iAttacker, AuthId_SteamID64, sAttackerID, sizeof(sAttackerID));
			GetClientAuthId(client, AuthId_SteamID64, sClientID, sizeof(sClientID));
		}
		
		if (strlen(sAttackerID) > 2 && strlen(sClientID) > 2)
		{
			Format(sAttackerID, sizeof(sAttackerID), " (%s)", sAttackerID);
			Format(sClientID, sizeof(sClientID), " (%s)", sClientID);
		}
	}

	if (g_iRole[iAttacker] == TTT_TEAM_INNOCENT && g_iRole[client] == TTT_TEAM_INNOCENT)
	{
		Format(iItem, sizeof(iItem), "-> [%N%s (Innocent) damaged %N%s (Innocent) for %i damage with %s] - BAD ACTION", iAttacker, sAttackerID, client, sClientID, damage, sWeapon);
		addArrayTime(iItem);
	}
	else if (g_iRole[iAttacker] == TTT_TEAM_INNOCENT && g_iRole[client] == TTT_TEAM_TRAITOR)
	{
		Format(iItem, sizeof(iItem), "-> [%N%s (Innocent) damaged %N%s (Traitor) for %i damage with %s]", iAttacker, sAttackerID, client, sClientID, damage, sWeapon);
		addArrayTime(iItem);
	}
	else if (g_iRole[iAttacker] == TTT_TEAM_INNOCENT && g_iRole[client] == TTT_TEAM_DETECTIVE)
	{
		Format(iItem, sizeof(iItem), "-> [%N%s (Innocent) damaged %N%s (Detective) for %i damage with %s] - BAD ACTION", iAttacker, sAttackerID, client, sClientID, damage, sWeapon);
		addArrayTime(iItem);
	}
	else if (g_iRole[iAttacker] == TTT_TEAM_TRAITOR && g_iRole[client] == TTT_TEAM_INNOCENT)
	{
		Format(iItem, sizeof(iItem), "-> [%N%s (Traitor) damaged %N%s (Innocent) for %i damage with %s]", iAttacker, sAttackerID, client, sClientID, damage, sWeapon);
		addArrayTime(iItem);

	}
	else if (g_iRole[iAttacker] == TTT_TEAM_TRAITOR && g_iRole[client] == TTT_TEAM_TRAITOR)
	{
		Format(iItem, sizeof(iItem), "-> [%N%s (Traitor) damaged %N%s (Traitor) for %i damage with %s] - BAD ACTION", iAttacker, sAttackerID, client, sClientID, damage, sWeapon);
		addArrayTime(iItem);

	}
	else if (g_iRole[iAttacker] == TTT_TEAM_TRAITOR && g_iRole[client] == TTT_TEAM_DETECTIVE)
	{
		Format(iItem, sizeof(iItem), "-> [%N%s (Traitor) damaged %N%s (Detective) for %i damage with %s]", iAttacker, sAttackerID, client, sClientID, damage, sWeapon);
		addArrayTime(iItem);
	}
	else if (g_iRole[iAttacker] == TTT_TEAM_DETECTIVE && g_iRole[client] == TTT_TEAM_INNOCENT)
	{
		Format(iItem, sizeof(iItem), "-> [%N%s (Detective) damaged %N%s (Innocent) for %i damage with %s] - BAD ACTION", iAttacker, sAttackerID, client, sClientID, damage, sWeapon);
		addArrayTime(iItem);

	}
	else if (g_iRole[iAttacker] == TTT_TEAM_DETECTIVE && g_iRole[client] == TTT_TEAM_TRAITOR)
	{
		Format(iItem, sizeof(iItem), "-> [%N%s (Detective) damaged %N%s (Traitor) for %i damage with %s]", iAttacker, sAttackerID, client, sClientID, damage, sWeapon);
		addArrayTime(iItem);
	}
	else if (g_iRole[iAttacker] == TTT_TEAM_DETECTIVE && g_iRole[client] == TTT_TEAM_DETECTIVE)
	{
		Format(iItem, sizeof(iItem), "-> [%N%s (Detective) damaged %N%s (Detective) for %i damage with %s] - BAD ACTION", iAttacker, sAttackerID, client, sClientID, damage, sWeapon);
		addArrayTime(iItem);
	}
}

public Action OnPlayerRunCmd(int client, int &buttons)
{
	if (g_iConfig[bdenyFire] && g_iRole[client] == TTT_TEAM_UNASSIGNED && ((buttons & IN_ATTACK) || (buttons & IN_ATTACK2)))
	{
		buttons &= ~IN_ATTACK;
		buttons &= ~IN_ATTACK2;
		return Plugin_Changed;
	}

	int button = -1;
	for (int i = 0; i < 25; i++)
	{
		button = (1 << i);

		if ((buttons & button))
		{
			if (!(g_iLastButtons[client] & button))
			{
				Call_StartForward(g_hOnButtonPress);
				Call_PushCell(client);
				Call_PushCell(button);
				Call_Finish();
			}
		}
		else if ((g_iLastButtons[client] & button))
		{
			Call_StartForward(g_hOnButtonRelease);
			Call_PushCell(client);
			Call_PushCell(button);
			Call_Finish();
		}
	}

	g_iLastButtons[client] = buttons;

	return Plugin_Continue;
}

public int TTT_OnButtonPress(int client, int button)
{
	if (!IsClientInGame(client))
	{
		return;
	}

	if (button & IN_USE)
	{
		g_bHoldingProp[client] = true;

		int iEntity = GetClientAimTarget(client, false);
		if (iEntity > 0)
		{
			float OriginG[3], TargetOriginG[3];
			GetClientEyePosition(client, TargetOriginG);
			GetEntPropVector(iEntity, Prop_Data, "m_vecOrigin", OriginG);
			if (GetVectorDistance(TargetOriginG, OriginG, false) > 90.0)
				return;

			int iSize = g_aRagdoll.Length;
			if (iSize == 0)
			{
				return;
			}

			int iRagdollC[Ragdolls];
			int entity;

			for (int i = 0; i < iSize; i++)
			{
				g_aRagdoll.GetArray(i, iRagdollC[0]);
				entity = EntRefToEntIndex(iRagdollC[Ent]);
				if (entity == iEntity)
				{
					if (IsPlayerAlive(client) && !g_bIsChecking[client])
					{
						g_bIsChecking[client] = true;
						Action res = Plugin_Continue;
						Call_StartForward(g_hOnBodyChecked);
						Call_PushCell(client);
						Call_PushArrayEx(iRagdollC[0], sizeof(iRagdollC), SM_PARAM_COPYBACK);
						Call_Finish(res);
						if (res == Plugin_Stop)
						{
							return;
						}
						else if (res == Plugin_Changed)
						{
							g_aRagdoll.SetArray(i, iRagdollC[0]);
							return;
						}

						InspectBody(client, iRagdollC[Victim], iRagdollC[Attacker], RoundToNearest(GetGameTime() - iRagdollC[GameTime]), iRagdollC[Weaponused], iRagdollC[VictimName], iRagdollC[AttackerName]);

						if (!iRagdollC[Found] && IsPlayerAlive(client))
						{
							iRagdollC[Found] = true;

							if (IsClientInGame(iRagdollC[Victim]))
							{
								g_bFound[iRagdollC[Victim]] = true;
							}

							if (iRagdollC[VictimTeam] == TTT_TEAM_INNOCENT)
							{
								LoopValidClients(j)
									CPrintToChat(j, g_iConfig[spluginTag], "Found Innocent", j, client, iRagdollC[VictimName]);
								SetEntityRenderColor(iEntity, 0, 255, 0, 255);
							}
							else if (iRagdollC[VictimTeam] == TTT_TEAM_DETECTIVE)
							{
								LoopValidClients(j)
									CPrintToChat(j, g_iConfig[spluginTag], "Found Detective", j, client, iRagdollC[VictimName]);
								SetEntityRenderColor(iEntity, 0, 0, 255, 255);
							}
							else if (iRagdollC[VictimTeam] == TTT_TEAM_TRAITOR)
							{
								LoopValidClients(j)
									CPrintToChat(j, g_iConfig[spluginTag], "Found Traitor", j, client, iRagdollC[VictimName]);
								SetEntityRenderColor(iEntity, 255, 0, 0, 255);
							}

							TeamTag(iRagdollC[Victim]);

							Call_StartForward(g_hOnBodyFound);
							Call_PushCell(client);
							Call_PushCell(iRagdollC[Victim]);
							Call_PushString(iRagdollC[VictimName]);
							Call_Finish();
						}
						g_aRagdoll.SetArray(i, iRagdollC[0]);
						break;
					}
				}
			}
		}
	}
}

public int TTT_OnButtonRelease(int client, int button)
{
	if (button & IN_USE)
	{
		g_bHoldingProp[client] = false;
		g_bIsChecking[client] = false;
	}
}

public Action Command_Say(int client, const char[] command, int argc)
{
	if (!TTT_IsClientValid(client) || !IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}

	char sText[MAX_MESSAGE_LENGTH];
	GetCmdArgString(sText, sizeof(sText));

	StripQuotes(sText);

	if (sText[0] == '@')
	{
		return Plugin_Continue;
	}

	return Plugin_Continue;
}

public Action Command_SayTeam(int client, const char[] command, int argc)
{
	if (!TTT_IsClientValid(client) || !IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}

	char sText[MAX_MESSAGE_LENGTH];
	GetCmdArgString(sText, sizeof(sText));

	StripQuotes(sText);

	if (strlen(sText) < 2)
	{
		return Plugin_Handled;
	}

	if (sText[0] == '@')
	{
		return Plugin_Continue;
	}

	if (g_iRole[client] == TTT_TEAM_TRAITOR)
	{
		LoopValidClients(i)
		{
			if (g_iRole[i] == TTT_TEAM_TRAITOR || g_iConfig[btChatToDead] && !IsPlayerAlive(i))
			{
				EmitSoundToClient(i, SND_TCHAT);
				CPrintToChat(i, "%T", "T channel", i, client, sText);
			}
		}

		return Plugin_Handled;
	}
	else if (g_iRole[client] == TTT_TEAM_DETECTIVE)
	{
		LoopValidClients(i)
		{
			if (g_iRole[i] == TTT_TEAM_DETECTIVE || g_iConfig[bdChatToDead] && !IsPlayerAlive(i))
			{
				EmitSoundToClient(i, SND_TCHAT);
				CPrintToChat(i, "%T", "D channel", i, client, sText);
			}
		}

		return Plugin_Handled;
	}
	return Plugin_Handled;
}

stock void InspectBody(int client, int victim, int attacker, int time, const char[] weapon, const char[] victimName, const char[] attackerName)
{
	char team[32];
	if (g_iRole[victim] == TTT_TEAM_TRAITOR)
	{
		Format(team, sizeof(team), "%T", "Traitors", client);
	}
	else if (g_iRole[victim] == TTT_TEAM_DETECTIVE)
	{
		Format(team, sizeof(team), "%T", "Detectives", client);
	}
	else if (g_iRole[victim] == TTT_TEAM_INNOCENT)
	{
		Format(team, sizeof(team), "%T", "Innocents", client);
	}

	Handle menu = CreateMenu(BodyMenuHandler);
	char sBuffer[128];

	SetMenuTitle(menu, "%T", "Inspected body. The extracted data are the following", client);

	Format(sBuffer, sizeof(sBuffer), "%T", "Victim name", client, victimName);
	AddMenuItem(menu, "", sBuffer);

	Format(sBuffer, sizeof(sBuffer), "%T", "Team victim", client, team);
	AddMenuItem(menu, "", sBuffer);

	if (g_iRole[client] == TTT_TEAM_DETECTIVE)
	{
		Format(sBuffer, sizeof(sBuffer), "%T", "Elapsed since his death", client, time);
		AddMenuItem(menu, "", sBuffer);

		if (attacker > 0 && attacker != victim)
		{
			Format(sBuffer, sizeof(sBuffer), "%T", "The weapon used has been", client, weapon);
			AddMenuItem(menu, "", sBuffer);
		}
		else
		{
			Format(sBuffer, sizeof(sBuffer), "%T", "The weapon used has been: himself (suicide)", client);
			AddMenuItem(menu, "", sBuffer);
		}
	}

	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, 15);

}

public int BodyMenuHandler(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_End)
	{
		delete menu;
	}
}

stock int addKarma(int client, int karma, bool message = false)
{
	if (!g_bRoundStarted)
	{
		return -1;
	}

	g_iKarma[client] += karma;

	if (g_iKarma[client] > g_iConfig[imaxKarma])
	{
		g_iKarma[client] = g_iConfig[imaxKarma];
	}

	if (g_iConfig[bshowEarnKarmaMessage] && message)
	{
		if (g_iConfig[imessageTypKarma] == 1)
		{
			PrintHintText(client, "%T", "karma earned", client, karma, g_iKarma[client]);
		}
		else
		{
			CPrintToChat(client, g_iConfig[spluginTag], "karma earned", client, karma, g_iKarma[client]);
		}
	}

	UpdatePlayer(client);
	
	return g_iKarma[client];
}

stock int setKarma(int client, int karma, bool force = false)
{
	if (!force && !g_bRoundStarted)
	{
		return -1;
	}

	g_iKarma[client] = karma;

	if (g_iKarma[client] > g_iConfig[imaxKarma])
	{
		g_iKarma[client] = g_iConfig[imaxKarma];
	}

	UpdatePlayer(client);
	
	return g_iKarma[client];
}

stock int subtractKarma(int client, int karma, bool message = false)
{
	if (!g_bRoundStarted)
	{
		return -1;
	}

	g_iKarma[client] -= karma;

	if (g_iConfig[bshowLoseKarmaMessage] && message)
	{
		if (g_iConfig[imessageTypKarma] == 1)
		{
			PrintHintText(client, "%T", "lost karma", client, karma, g_iKarma[client]);
		}
		else
		{
			CPrintToChat(client, g_iConfig[spluginTag], "lost karma", client, karma, g_iKarma[client]);
		}
	}

	UpdatePlayer(client);
	
	return g_iKarma[client];
}

stock void addArrayTime(char[] message)
{
	if (g_iTeamSelectTime > 0)
	{
		int iTime = GetTime() - g_iTeamSelectTime;
		int iMin = ((iTime / 60) % 60);
		int iSec = (iTime % 60);

		Format(message, TTT_ITEM_SIZE, "[%02i:%02i] %s", iMin, iSec, message);
	}
	g_aLogs.PushString(message);
}

stock void ClearTimer(Handle &timer)
{
	if (timer != null)
	{
		KillTimer(timer);
		timer = null;
	}
}

public Action Command_LAW(int client, const char[] command, int argc)
{
	if (!TTT_IsClientValid(client))
	{
		return Plugin_Continue;
	}

	if (g_iConfig[ballowFlash] && IsPlayerAlive(client))
	{
		EmitSoundToAllAny(SND_FLASHLIGHT, client, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.6);
		SetEntProp(client, Prop_Send, "m_fEffects", GetEntProp(client, Prop_Send, "m_fEffects") ^ 4);
	}

	if (g_iConfig[bblockLookAtWeapon])
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

stock void manageRDM(int client)
{
	if (!IsClientInGame(client))
	{
		return;
	}

	if (g_iConfig[bignoreRDMMenu])
	{
		return;
	}

	int iAttacker = g_iRDMAttacker[client];
	if (!IsClientInGame(iAttacker) || iAttacker < 0 || iAttacker > MaxClients)
	{
		CPrintToChat(client, g_iConfig[spluginTag], "The player who RDM'd you is no longer available", client);
		return;
	}
	char sAttackerName[MAX_NAME_LENGTH];
	GetClientName(iAttacker, sAttackerName, sizeof(sAttackerName));

	char display[256], sForgive[64], sPunish[64];
	Format(display, sizeof(display), "%T", "You were RDM'd", client, sAttackerName);
	Format(sForgive, sizeof(sForgive), "%T", "Forgive", client);
	Format(sPunish, sizeof(sPunish), "%T", "Punish", client);

	Handle menuHandle = CreateMenu(manageRDMHandle);
	SetMenuTitle(menuHandle, display);
	AddMenuItem(menuHandle, "Forgive", sForgive);
	AddMenuItem(menuHandle, "Punish", sPunish);
	DisplayMenu(menuHandle, client, 10);
}

public int manageRDMHandle(Menu menu, MenuAction action, int client, int option)
{
	if (1 > client || client > MaxClients || !IsClientInGame(client))
	{
		return;
	}

	int iAttacker = g_iRDMAttacker[client];
	if (1 > iAttacker || iAttacker > MaxClients || !IsClientInGame(iAttacker))
	{
		return;
	}

	if (action == MenuAction_Select)
	{
		char info[100];
		GetMenuItem(menu, option, info, sizeof(info));
		if (StrEqual(info, "Forgive", false))
		{
			CPrintToChat(client, g_iConfig[spluginTag], "Choose Forgive Victim", client, iAttacker);
			CPrintToChat(iAttacker, g_iConfig[spluginTag], "Choose Forgive Attacker", iAttacker, client);
			g_iRDMAttacker[client] = -1;
		}
		if (StrEqual(info, "Punish", false))
		{
			LoopValidClients(i)
				CPrintToChat(i, g_iConfig[spluginTag], "Choose Punish", i, client, iAttacker);
			ServerCommand("sm_slay #%i 2", GetClientUserId(iAttacker));
			g_iRDMAttacker[client] = -1;
		}
	}
	else if (action == MenuAction_Cancel)
	{
		CPrintToChat(client, g_iConfig[spluginTag], "Choose Forgive Victim", client, iAttacker);
		CPrintToChat(iAttacker, g_iConfig[spluginTag], "Choose Forgive Attacker", iAttacker, client);
		g_iRDMAttacker[client] = -1;
	}
	else if (action == MenuAction_End)
	{
		delete menu;
		CPrintToChat(client, g_iConfig[spluginTag], "Choose Forgive Victim", client, iAttacker);
		CPrintToChat(iAttacker, g_iConfig[spluginTag], "Choose Forgive Attacker", iAttacker, client);
		g_iRDMAttacker[client] = -1;
		
		delete menu;
	}
}

public Action Timer_RDMTimer(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	g_hRDMTimer[client] = null;
	manageRDM(client);
	return Plugin_Stop;
}

public Action Command_SetRole(int client, int args)
{
	if (!TTT_IsClientValid(client))
	{
		return Plugin_Handled;
	}

	if (!TTT_HasFlags(client, g_iConfig[sSetRole]))
	{
		return Plugin_Handled;
	}

	if (args < 2 || args > 3)
	{
		ReplyToCommand(client, "[SM] Usage: sm_role <#userid|name> <role>");
		ReplyToCommand(client, "[SM] Roles: 1 - Innocent | 2 - Traitor | 3 - Detective");
		return Plugin_Handled;
	}
	char arg1[32];
	char arg2[32];
	
	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));
	
	int target = FindTarget(client, arg1);

	if (target == -1)
	{
		return Plugin_Handled;
	}

	if (!IsPlayerAlive(target))
	{
		ReplyToCommand(client, "[SM] This command can only be used to alive players!");
		return Plugin_Handled;
	}

	int iRole = StringToInt(arg2);
	int iOld = TTT_GetClientRole(target);
	
	if (iRole < 1 || iRole > 3)
	{
		ReplyToCommand(client, "[SM] Roles: 1 - Innocent | 2 - Traitor | 3 - Detective");
		return Plugin_Handled;
	}
	else if (iRole == 1)
	{
		if (iOld == TTT_TEAM_INNOCENT)
		{
			return Plugin_Handled;
		}
		
		g_iRole[target] = TTT_TEAM_INNOCENT;
		
		TeamInitialize(target);
		CS_SetClientClanTag(target, " ");
		CPrintToChat(client, g_iConfig[spluginTag], "Player is Now Innocent", client, target);
		LogAction(client, target, "\"%L\" set the role of \"%L\" to \"%s\"", client, target, "Innocent");
		
		return Plugin_Handled;
	}
	else if (iRole == 2)
	{
		if (iOld == TTT_TEAM_TRAITOR)
		{
			return Plugin_Handled;
		}
		
		g_iRole[target] = TTT_TEAM_TRAITOR;
		
		TeamInitialize(target);
		CS_SetClientClanTag(target, " ");
		CPrintToChat(client, g_iConfig[spluginTag], "Player is Now Traitor", client, target);
		LogAction(client, target, "\"%L\" set the role of \"%L\" to \"%s\"", client, target, "Traitor");
		
		return Plugin_Handled;
	}
	else if (iRole == 3)
	{
		if (iOld == TTT_TEAM_DETECTIVE)
		{
			return Plugin_Handled;
		}
		
		g_iRole[target] = TTT_TEAM_DETECTIVE;
		
		TeamInitialize(target);
		CPrintToChat(client, g_iConfig[spluginTag], "Player is Now Detective", client, target);
		LogAction(client, target, "\"%L\" set the role of \"%L\" to \"%s\"", client, target, "Detective");
		
		return Plugin_Handled;
	}
	return Plugin_Handled;
}

public Action Command_SetKarma(int client, int args)
{
	if (!TTT_IsClientValid(client))
	{
		return Plugin_Handled;
	}

	if (!TTT_HasFlags(client, g_iConfig[sKarmaReset]))
	{
		return Plugin_Handled;
	}

	if (args < 2 || args > 3)
	{
		ReplyToCommand(client, "[SM] Usage: sm_setkarma <#userid|name> <karma>");

		return Plugin_Handled;
	}

	char arg1[32];
	char arg2[32];
	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));

	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS];
	int target_count;
	bool tn_is_ml;

	if ((target_count = ProcessTargetString(arg1, client, target_list, MAXPLAYERS, COMMAND_FILTER_CONNECTED, target_name, sizeof(target_name), tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}

	for (int i = 0; i < target_count; i++)
	{
		int target = target_list[i];

		if (target == -1)
		{
			ReplyToCommand(client, "[SM] Invalid target.");
			return Plugin_Handled;
		}

		if (!g_bKarma[target])
		{
			ReplyToCommand(client, "[SM] Player data not loaded yet.");
			return Plugin_Handled;
		}

		int karma = StringToInt(arg2);

		setKarma(target, karma, true);

		CPrintToChat(client, g_iConfig[spluginTag], "AdminSet", client, target, karma, "Karma");
		LogAction(client, target, "\"%L\" set the karma of \"%L\" to \"%i\"", client, target, karma);
	}

	return Plugin_Continue;
}

public Action Command_ReloadCFG(int client, int args)
{
	if (!TTT_IsClientValid(client))
	{
		return Plugin_Handled;
	}

	if (!TTT_HasFlags(client, g_iConfig[sReloadCFG]))
	{
		return Plugin_Handled;
	}

	SetupConfig();
	
	return Plugin_Handled;
}

public Action Command_Status(int client, int args)
{
	if (!TTT_IsClientValid(client))
	{
		return Plugin_Handled;
	}

	if (g_iRole[client] == TTT_TEAM_UNASSIGNED)
	{
		CPrintToChat(client, g_iConfig[spluginTag], "You Are Unassigned", client);
	}
	else if (g_iRole[client] == TTT_TEAM_INNOCENT)
	{
		CPrintToChat(client, g_iConfig[spluginTag], "You Are Now Innocent", client);
	}
	else if (g_iRole[client] == TTT_TEAM_DETECTIVE)
	{
		CPrintToChat(client, g_iConfig[spluginTag], "You Are Now Detective", client);
	}
	else if (g_iRole[client] == TTT_TEAM_TRAITOR)
	{
		CPrintToChat(client, g_iConfig[spluginTag], "You Are Now Traitor", client);
	}

	return Plugin_Handled;
}

public Action Timer_5(Handle timer)
{
	LoopValidClients(i)
	{
		Call_StartForward(g_hOnUpdate5);
		Call_PushCell(i);
		Call_Finish();

		if (GetClientTeam(i) != CS_TEAM_CT && GetClientTeam(i) != CS_TEAM_T)
		{
			continue;
		}

		if (IsFakeClient(i))
		{
			continue;
		}

		if (!IsPlayerAlive(i))
		{
			continue;
		}

		if (g_bKarma[i] && g_iConfig[ikarmaBan] != 0 && g_iKarma[i] <= g_iConfig[ikarmaBan])
		{
			BanBadPlayerKarma(i);
		}
	}

	if (g_bRoundStarted)
	{
		CheckTeams();
	}
	else if (g_bCheckPlayers)
	{
		CheckPlayers();
	}

	Call_StartForward(g_hOnUpdate5);
	Call_Finish();
}

void CheckPlayers()
{
	int iCount = 0;
	LoopValidClients(i)
	{
		if (GetClientTeam(i) != CS_TEAM_CT && GetClientTeam(i) != CS_TEAM_T)
		{
			continue;
		}

		if (IsFakeClient(i))
		{
			continue;
		}

		iCount++;
	}

	if (iCount >= g_iConfig[irequiredPlayers])
	{
		g_bCheckPlayers = false;

		if (!g_bDebug)
		{
			CS_TerminateRound(3.0, CSRoundEnd_Draw);
		}
	}
}

public void OnEntityCreated(int entity, const char[] name)
{
	if (StrEqual(name, "func_button"))
	{
		char targetName[128];
		GetEntPropString(entity, Prop_Data, "m_iName", targetName, sizeof(targetName));
		
		if (StrEqual(targetName, "Destroy_Trigger", false))
		{
			SDKHook(entity, SDKHook_Use, OnUse);
		}
	}
	else
	{
		for (int i = 0; i < sizeof(g_sRemoveEntityList); i++)
		{
			if (!StrEqual(name, g_sRemoveEntityList[i]))
			{
				continue;
			}

			if (g_iConfig[bremoveBomb] && StrEqual("func_bombtarget", g_sRemoveEntityList[i], false))
			{
				AcceptEntityInput(entity, "kill");
			}
			else if (g_iConfig[bremoveBuyzone] && StrEqual("func_buyzone", g_sRemoveEntityList[i], false))
			{
				AcceptEntityInput(entity, "kill");
			}
			else if (g_iConfig[bremoveHostages])
			{
				AcceptEntityInput(entity, "kill");
			}

			break;
		}
	}
}

public Action OnUse(int entity, int activator, int caller, UseType type, float value)
{
	if (activator < 1 || activator > MaxClients || !IsClientInGame(activator))
	{
		return Plugin_Continue;
	}

	if (g_bInactive)
	{
		return Plugin_Handled;
	}

	else
	{
		if (g_iRole[activator] == TTT_TEAM_INNOCENT || g_iRole[activator] == TTT_TEAM_DETECTIVE || g_iRole[activator] == TTT_TEAM_UNASSIGNED)
		{
			ServerCommand("sm_slay #%i 2", GetClientUserId(activator));

			LoopValidClients(i)
			{
				CPrintToChat(i, g_iConfig[spluginTag], "Triggered Falling Building", i, activator);
			}
		}
	}
	return Plugin_Continue;
}

stock void nameCheck(int client, char name[MAX_NAME_LENGTH])
{
	for (int i; i < g_iBadNameCount; i++)
	{
		if (StrContains(g_sBadNames[i], name, false) != -1)
		{
			KickClient(client, "%T", "Kick Bad Name", client, g_sBadNames[i]);
		}
	}
}

public void OnWeaponPostSwitch(int client, int weapon)
{
	char weaponName[64];
	GetClientWeapon(client, weaponName, sizeof(weaponName));
	if (StrContains(weaponName, "silence") != -1)
	{
		g_bHoldingSilencedWep[client] = true;
	}
	else
	{
		g_bHoldingSilencedWep[client] = false;
	}
}

public Action Command_KarmaReset(int client, int args)
{
	if (!TTT_IsClientValid(client))
	{
		return Plugin_Handled;
	}

	if (!TTT_HasFlags(client, g_iConfig[sKarmaReset]))
	{
		return Plugin_Handled;
	}

	LoopValidClients(i)
	{
		if (!IsFakeClient(i))
		{
			CPrintToChat(client, g_iConfig[spluginTag], "AdminSet", client, i, g_iConfig[istartKarma], "Karma");
			setKarma(i, g_iConfig[istartKarma], true);
			LogAction(client, i, "\"%L\" reset the karma of \"%L\" to \"%i\"", client, i, g_iConfig[istartKarma]);
		}
	}
	
	return Plugin_Handled;
}

void CheckTeams()
{
	int iT = 0;
	int iD = 0;
	int iI = 0;

	LoopValidClients(i)
	{
		if (IsPlayerAlive(i))
		{
			if (g_iRole[i] == TTT_TEAM_DETECTIVE)
			{
				CS_SetClientClanTag(i, "DETECTIVE");
				iD++;
			}
			else if (g_iRole[i] == TTT_TEAM_TRAITOR)
			{
				iT++;
			}
			else if (g_iRole[i] == TTT_TEAM_INNOCENT)
			{
				iI++;
			}
		}
		else
		{
			if (g_iRole[i] == TTT_TEAM_UNASSIGNED)
			{
				g_bFound[i] = true;
				CS_SetClientClanTag(i, "UNASSIGNED");
			}
		}
	}

	if (g_iConfig[bignoreDeaths])
	{
		return;
	}

	if (iD == 0 && iI == 0)
	{
		g_bRoundStarted = false;
		g_bRoundEnded = true;

		if (!g_bDebug)
		{
			CS_TerminateRound(7.0, CSRoundEnd_TerroristWin);
		}
	}
	else if (iT == 0)
	{
		g_bRoundStarted = false;
		g_bRoundEnded = true;

		if (!g_bDebug)
		{
			CS_TerminateRound(7.0, CSRoundEnd_CTWin);
		}
	}
}

stock void SetNoBlock(int client)
{
	SetEntData(client, g_iCollisionGroup, 2, 4, true);
}

stock void LoadBadNames()
{
	char sFile[PLATFORM_MAX_PATH + 1];
	BuildPath(Path_SM, sFile, sizeof(sFile), "configs/ttt/badnames.ini");

	Handle hFile = OpenFile(sFile, "rt");

	if (hFile == null)
	{
		SetFailState("[TTT] Can't open File: %s", sFile);
	}

	char sLine[MAX_NAME_LENGTH];

	while (!IsEndOfFile(hFile) && ReadFileLine(hFile, sLine, sizeof(sLine)))
	{
		if (strlen(sLine) > 1)
		{
			strcopy(g_sBadNames[g_iBadNameCount], sizeof(g_sBadNames[]), sLine);
			g_iBadNameCount++;
		}
	}

	delete hFile;
}

stock void LoadClientKarma(int userid)
{
	int client = GetClientOfUserId(userid);

	if (!IsFakeClient(client))
	{
		char sCommunityID[64];

		if (!GetClientAuthId(client, AuthId_SteamID64, sCommunityID, sizeof(sCommunityID)))
		{
			LogToFileEx(g_iConfig[serrFile], "(LoadClientKarma) Auth failed: #%d", client);
			return;
		}

		char sQuery[2048];
		Format(sQuery, sizeof(sQuery), "SELECT `karma` FROM `ttt` WHERE `communityid`= \"%s\";", sCommunityID);

		if (g_bDebug)
		{
			LogToFileEx(g_iConfig[slogFile], sQuery);
		}

		if (g_dDB != null)
		{
			g_dDB.Query(SQL_OnClientPostAdminCheck, sQuery, userid);
		}
	}
}

stock void UpdatePlayer(int client)
{
	char sCommunityID[64];

	if (!GetClientAuthId(client, AuthId_SteamID64, sCommunityID, sizeof(sCommunityID)))
	{
		LogToFileEx(g_iConfig[serrFile], "(UpdatePlayer) Auth failed: #%d", client);
		return;
	}

	char sQuery[2048];
	
	if (TTT_GetConnectionType() == dMySQL)
	{
		Format(sQuery, sizeof(sQuery), "INSERT INTO ttt (communityid, karma) VALUES (\"%s\", %d) ON DUPLICATE KEY UPDATE karma = %d;", sCommunityID, g_iKarma[client], g_iKarma[client]);
	}
	else
	{
		Format(sQuery, sizeof(sQuery), "INSERT OR REPLACE INTO ttt (communityid, karma) VALUES (\"%s\", %d);", sCommunityID, g_iKarma[client], g_iKarma[client]);
	}

	if (g_bDebug)
	{
		LogToFileEx(g_iConfig[slogFile], sQuery);
	}

	if (g_dDB != null)
	{
		g_dDB.Query(Callback_UpdatePlayer, sQuery, GetClientUserId(client));
	}
}

stock void StripAllWeapons(int client)
{
	if (!g_iConfig[bstripWeapons])
	{
		return;
	}

	int iEnt;
	for (int i = CS_SLOT_PRIMARY; i <= CS_SLOT_C4; i++)
	{
		while ((iEnt = GetPlayerWeaponSlot(client, i)) != -1)
		{
			TTT_SafeRemoveWeapon(client, iEnt);
		}
	}
}

stock void CheckClantag(int client)
{
	char sTag[32];
	CS_GetClientClanTag(client, sTag, sizeof(sTag));

	if (!ValidClantag(client, sTag))
	{
		if (!g_bRoundStarted)
		{
			CS_SetClientClanTag(client, " ");
		}
		else
		{

			if (!g_bFound[client])
			{
				if (g_iRole[client] == TTT_TEAM_UNASSIGNED)
				{
					CS_SetClientClanTag(client, "UNASSIGNED");
				}
				else if (g_iRole[client] == TTT_TEAM_DETECTIVE)
				{
					CS_SetClientClanTag(client, "DETECTIVE");
				}
				else
				{
					CS_SetClientClanTag(client, " ");
				}
			}
			else if (g_bFound[client])
			{
				TeamTag(client);
			}
		}
	}
}

stock bool ValidClantag(int client, const char[] sTag)
{
	if (StrContains(sTag, "DETECTIVE", false) != -1 || StrContains(sTag, "TRAITOR", false) != -1 || StrContains(sTag, "INNOCENT", false) != -1 || StrContains(sTag, "UNASSIGNED", false) != -1)
	{
		return true;
	}

	if (StrEqual(sTag, " ", false))
	{
		return true;
	}

	return false;
}

void GiveWeaponsOnFailStart()
{
	if (g_iConfig[bGiveWeaponsOnFailStart] && g_iConfig[bEnableDamage])
	{
		char sWeapon[32];

		LoopValidClients(i)
		{
			if (GetClientTeam(i) != CS_TEAM_CT && GetClientTeam(i) != CS_TEAM_T || IsFakeClient(i))
			{
				continue;
			}

			if (IsPlayerAlive(i))
			{
				GivePlayerItem(i, "weapon_knife");

				Format(sWeapon, sizeof(sWeapon), "weapon_%s", g_iConfig[sFSSecondary]);
				GivePlayerItem(i, sWeapon);

				Format(sWeapon, sizeof(sWeapon), "weapon_%s", g_iConfig[sFSPrimary]);
				GivePlayerItem(i, sWeapon);
			}
		}
	}
}
