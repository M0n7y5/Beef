using System;

namespace Tests
{
	class Initializers
	{
		struct StructA
		{
			public int mA = 123;
			public int mB;
			public int mC;
			public int mD;

			public int ValC
			{
				set mut
				{
					mC = value;
				}
			}

			public void Add(float val, float? val2 = 234) mut
			{
				mD += (int)val;
				mD += (int)val2 * 10;
			}

			public void Add(int val) mut
			{
				mD += (int)val * 1000;
			}
		}

		struct StructG<T>
		{
			public int mA;
			public int mB;

			public this()
			{
				mA = 0;
				mB = 0;
			}

			public this(int a)
			{
				mA = a;
				mB = 0;
			}
		}

		struct StructG2<T, T2>
		{
			public int mB;
		}

		static StructG<int> sG = StructG<int>() { mB = 1 };

		static int GetB(StructG<int> val) => val.mB;

		static StructG<int> MakeG() => StructG<int>() { mB = 2 };

		[Test]
		public static void TestGenericValueInitializers()
		{
			int d = -1;
			let ga = StructG<int>() { mB = 3 };
			Test.Assert(ga.mB == 3);
			let gb = StructG<int>(4) { mB = 5 };
			Test.Assert((gb.mA == 4) && (gb.mB == 5));
			let gc = StructG<StructG<int>>() { mB = 6 };
			Test.Assert(gc.mB == 6);
			let gd = StructG2<int, float>() { mB = 7 };
			Test.Assert(gd.mB == 7);
			Test.Assert(GetB(StructG<int>() { mB = 8 }) == 8);
			let ge = (d < 0) ? StructG<int>() { mB = 9 } : StructG<int>() { mB = 10 };
			Test.Assert(ge.mB == 9);
			Test.Assert(sG.mB == 1);
			Test.Assert(MakeG().mB == 2);
		}

		[Test]
		public static void TestBasics()
		{
			StructA sa = .() { mB = 345, ValC = 456, 567.8f, 789};
			Test.Assert(sa.mA == 123);
			Test.Assert(sa.mB == 345);
			Test.Assert(sa.mC == 456);
			Test.Assert(sa.mD == 791907);
		}
	}
}
