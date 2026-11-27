using System;
using System.Reflection;

namespace Tests
{
	class ComptimeReturnAttributes
	{
		[AttributeUsage(.ReturnValue | .Parameter)]
		struct TagAttribute : Attribute
		{
			public int32 mId;
			public int32 Extra;

			public this(int32 id)
			{
				mId = id;
				Extra = 0;
			}
		}

		struct Target
		{
			[return: Tag(1, Extra=2)]
			[return: Tag(3)]
			public static int Call([Tag(4)] int a)
			{
				return a;
			}
		}

		static class Reader
		{
			[OnCompile(.TypeInit), Comptime]
			static void Generate()
			{
				let ret = scope String();
				let outOfRange = scope String();
				for (let method in typeof(Target).GetMethods())
				{
					if (method.Name != "Call")
						continue;
					if (method.GetReturnCustomAttribute<TagAttribute>() case .Ok(let first))
						ret.AppendF($"{first.mId}:{first.Extra};");
					for (let variant in method.GetReturnCustomAttributes())
						ret.AppendF($"{variant.VariantType.GetName(.. scope .())};");
					for (let attr in method.GetReturnCustomAttributes<TagAttribute>())
						ret.AppendF($"{attr.mId};");
#if BF_64_BIT
					int[5] outOfRangeIndices = .(-1, 1, int32.MaxValue, 0x1'0000'0000, 0xFFFF'FFFF);
#else
					int[3] outOfRangeIndices = .(-1, 1, int32.MaxValue);
#endif
					for (let paramIdx in outOfRangeIndices)
					{
						for (let attr in method.GetParamCustomAttributes<TagAttribute>(paramIdx))
							outOfRange.AppendF($"{attr.mId};");
					}
				}
				Compiler.EmitTypeBody(typeof(Self), scope $"""
					public const String cReturn = "{ret}";
					public const String cOutOfRange = "{outOfRange}";
					""");
			}
		}

		[Test]
		public static void TestReadAtComptime()
		{
			Test.Assert(Reader.cReturn == "1:2;TagAttribute;TagAttribute;1;3;");
			Test.Assert(Reader.cOutOfRange == "");
		}
	}
}
