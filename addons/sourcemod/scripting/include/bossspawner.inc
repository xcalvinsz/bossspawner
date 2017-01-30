/*
**
*/
#if defined _INCLUDE_included
 #endinput
#endif
#define _INCLUDE_included

methodmap Reference < ArrayStack
{	
	public Reference(int a)
	{
		ArrayStack stack = new ArrayStack();
		stack.Push(a);
		return view_as<Reference>(stack);
	}
	
	property int Value
	{
		public get()
		{
			int a = this.Pop();
			this.Push(a);
			return a;
		}
		public set(int a)
		{
			this.Pop();
			this.Push(a);
		}
	}
}

methodmap BossPack < DataPack
{
	public BossPack (int entity, Reference reference, int index, int timed)
	{
		DataPack pack = new DataPack();
		pack.WriteCell(EntIndexToEntRef(entity));
		pack.WriteCell(reference);
		pack.WriteCell(index);
		pack.WriteCell(timed); 
		return view_as<BossPack>(pack);
	}
	property int Entity
	{
		public set(int entity)
		{
			this.Reset();
			this.WriteCell(EntIndexToEntRef(entity));
		}
		public get()
		{
			this.Reset();
			return EntRefToEntIndex(this.ReadCell());
		}
	}
	property Reference Ref
	{
		public set(Reference reference)
		{
			this.Reset(); this.ReadCell();
			this.WriteCell(reference);
		}
		public get()
		{
			this.Reset(); this.ReadCell();
			return this.ReadCell();
		}
	}
	property int Index
	{
		public set(int index)
		{
			this.Reset(); this.ReadCell(); this.ReadCell();
			this.WriteCell(index);
		}
		public get()
		{
			this.Reset(); this.ReadCell(); this.ReadCell();
			return this.ReadCell();
		}
	}
	property bool Timed
	{
		public set(bool timed)
		{
			this.Reset(); this.ReadCell(); this.ReadCell(); this.ReadCell();
			this.WriteCell(timed);
		}
		public get()
		{
			this.Reset(); this.ReadCell(); this.ReadCell(); this.ReadCell();
			return this.ReadCell();
		}
	}
}

stock void SetEyeballLifetime(int duration)
{
	FindConVar("tf_eyeball_boss_lifetime").SetInt(duration, false, false);
}

stock void SetMerasmusLifetime(int duration)
{
	FindConVar("tf_merasmus_lifetime").SetInt(duration, false, false);
}

stock void SetSize(float value, int ent)
{
	SetEntPropFloat(ent, Prop_Send, "m_flModelScale", value);
}

stock void SetGlow(int ent, const char[] targetname, float kpos[3], const char[] sGlowValue)
{
	int glow = CreateEntityByName("tf_glow");
			
	DispatchKeyValue(glow, "glowcolor", sGlowValue);
	DispatchKeyValue(glow, "target", targetname);
	SetEntPropEnt(glow, Prop_Send, "m_hOwnerEntity", ent);
	TeleportEntity(glow, kpos, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(glow);
	
	SetVariantString("!activator");
	AcceptEntityInput(glow, "SetParent", ent, glow, 0);
	
	AcceptEntityInput(glow, "Enable");
}

stock void ResizeHitbox(int entity, float fScale)
{
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

stock void SetEntitySelfDestruct(int entity, float duration)
{
	char output[64]; 
	Format(output, sizeof(output), "OnUser1 !self:kill::%.1f:1", duration);
	SetVariantString(output);
	AcceptEntityInput(entity, "AddOutput"); 
	AcceptEntityInput(entity, "FireUser1");
}

stock int FindHealthBar()
{
	int ent;
	if ((ent = FindEntityByClassname(ent, "monster_resource")) == -1)
	{
		ent = CreateEntityByName("monster_resource");
		DispatchSpawn(ent);
	}
	return ent;
}