using System;
using System.Reflection;

namespace Tests
{
	class ComptimeAttributeCtor
	{
		[AttributeUsage(.Method)]
		struct FourAttribute : Attribute
		{
			public int32 mA, mB, mC, mD;

			public this(int32 a)
			{
				mA = a;
				mB = a + 1;
				mC = a + 2;
				mD = a + 3;
			}
		}

		[AttributeUsage(.Method)]
		struct SizedAttribute : Attribute
		{
			public int32[3] mItems;

			public this(int32[3] items)
			{
				mItems = items;
			}
		}

		[AttributeUsage(.Method)]
		struct SmallSizedAttribute : Attribute
		{
			public int16[2] mItems;

			public this(int16[2] items)
			{
				mItems = items;
			}
		}

		[AttributeUsage(.Method)]
		struct PairAttribute : Attribute
		{
			public int32 mA, mB;

			public this(int32 a)
			{
				mA = a;
				mB = a + 1;
			}
		}

		[AttributeUsage(.Struct)]
		struct EmitFourAttribute : Attribute, IComptimeTypeApply
		{
			public int32 mA, mB, mC, mD;

			public this(int32 a)
			{
				mA = a;
				mB = a * 2;
				mC = a * 3;
				mD = a * 4;
			}

			[Comptime]
			public void ApplyToType(Type type)
			{
				Compiler.EmitTypeBody(type, scope $"public const int32 cSum = {mA + mB + mC + mD};\n");
			}
		}

		struct Target
		{
			[Four(7), Sized(.(1, 2, 3)), SmallSized(.(4, 5)), Pair(9)]
			public void M()
			{
			}
		}

		[EmitFour(2)]
		struct Emitted
		{
		}

		static class Reader
		{
			[OnCompile(.TypeInit), Comptime]
			static void Generate()
			{
				let method = typeof(Target).GetMethod("M").Value;
				let four = method.GetCustomAttribute<FourAttribute>().Value;
				let sized = method.GetCustomAttribute<SizedAttribute>().Value;
				let small = method.GetCustomAttribute<SmallSizedAttribute>().Value;
				let pair = method.GetCustomAttribute<PairAttribute>().Value;
				Compiler.EmitTypeBody(typeof(Self), scope $"""
					public const String cFour = "{four.mA} {four.mB} {four.mC} {four.mD}";
					public const String cSized = "{sized.mItems[0]} {sized.mItems[1]} {sized.mItems[2]}";
					public const String cSmall = "{small.mItems[0]} {small.mItems[1]}";
					public const String cPair = "{pair.mA} {pair.mB}";
					""");
			}
		}

		[Test]
		public static void TestCtorValuesAtComptime()
		{
			Test.Assert(Reader.cFour == "7 8 9 10");
			Test.Assert(Reader.cSized == "1 2 3");
			Test.Assert(Reader.cSmall == "4 5");
			Test.Assert(Reader.cPair == "9 10");
			Test.Assert(Emitted.cSum == 20);
		}
	}
}
