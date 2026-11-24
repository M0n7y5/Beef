using System;
using System.Reflection;

namespace Tests
{
	class ComptimeParamAttributes
	{
		[AttributeUsage(.Parameter)]
		struct ParamTagAttribute : Attribute
		{
			public int32 mId;
			public int32 Extra;

			public this(int32 id)
			{
				mId = id;
				Extra = 0;
			}
		}

		[AttributeUsage(.Parameter)]
		struct OtherTagAttribute : Attribute
		{
		}

		struct Target
		{
			public static int Call([ParamTag(10, Extra=11)] int a, [OtherTag, ParamTag(20), ParamTag(30, Extra=31)] int b, int c)
			{
				return a + b + c;
			}
		}

		static class Reader
		{
			[OnCompile(.TypeInit), Comptime]
			static void Generate()
			{
				let first = scope String();
				let all = scope String();
				let typed = scope String();
				let outside = scope String();
				for (let method in typeof(Target).GetMethods())
				{
					if (method.Name != "Call")
						continue;
					for (int paramIdx < 3)
					{
						if (method.GetParamCustomAttribute<ParamTagAttribute>(paramIdx) case .Ok(let firstAttr))
							first.AppendF($"{firstAttr.mId}:{firstAttr.Extra};");
						else
							first.Append("none;");
						for (let variant in method.GetParamCustomAttributes(paramIdx))
							all.AppendF($"{variant.VariantType.GetName(.. scope .())};");
						for (let attr in method.GetParamCustomAttributes<ParamTagAttribute>(paramIdx))
							typed.AppendF($"{attr.mId}:{attr.Extra};");
					}
#if BF_64_BIT
					int[4] outOfRange = .(-1, 3, int32.MaxValue, 0x1'0000'0000);
#else
					int[3] outOfRange = .(-1, 3, int32.MaxValue);
#endif
					for (let paramIdx in outOfRange)
					{
						if (method.GetParamCustomAttribute<ParamTagAttribute>(paramIdx) case .Ok)
							outside.Append("found;");
						for (let variant in method.GetParamCustomAttributes(paramIdx))
							outside.Append("found;");
					}
				}
				Compiler.EmitTypeBody(typeof(Self), scope $"""
					public const String cFirst = "{first}";
					public const String cAll = "{all}";
					public const String cTyped = "{typed}";
					public const String cOutside = "{outside}";
					""");
			}
		}

		[Test]
		public static void TestReadAtComptime()
		{
			Test.Assert(Reader.cFirst == "10:11;20:0;none;");
			Test.Assert(Reader.cAll == "ParamTagAttribute;OtherTagAttribute;ParamTagAttribute;ParamTagAttribute;");
			Test.Assert(Reader.cTyped == "10:11;20:0;30:31;");
			Test.Assert(Reader.cOutside == "");
			Test.Assert(Target.Call(1, 2, 3) == 6);
		}
	}
}
