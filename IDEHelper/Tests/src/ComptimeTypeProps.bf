using System;

namespace Tests
{
	class ComptimeTypeProps
	{
		class Base
		{
		}

		class Derived : Base
		{
			public int mA;

			[OnCompile(.TypeInit), Comptime]
			static void Generate()
			{
				bool hasDecl = typeof(Self).TypeDeclaration != null;
				bool hasBase = typeof(Self).BaseType == typeof(Base);
				int fieldCount = typeof(Self).FieldCount;
				Compiler.EmitTypeBody(typeof(Self), scope $"public const bool cHasDecl = {(hasDecl ? "true" : "false")};\npublic const bool cHasBase = {(hasBase ? "true" : "false")};\npublic const int cFieldCount = {fieldCount};\n");
			}
		}

		[Test]
		public static void TestSelfMembersInTypeInit()
		{
			Test.Assert(Derived.cHasDecl);
			Test.Assert(Derived.cHasBase);
			Test.Assert(Derived.cFieldCount == 1);

			const int size = typeof(int32).Size;
			Test.Assert(size == 4);
			Type derived = typeof(Derived);
			Test.Assert(typeof(Derived).InstanceSize == derived.InstanceSize);
		}
	}
}
