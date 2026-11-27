using System;
using System.Reflection;

namespace Tests
{
	class AttributeNamedMembers
	{
		enum SmallEnum : int8
		{
			A = -3,
			B = 5
		}

		enum WideEnum : uint16
		{
			X = 1,
			Y = 0xF00D
		}

		enum PlainEnum
		{
			Red,
			Green,
			Blue
		}

		[AttributeUsage(.Class | .Method | .Field | .Parameter, .ReflectAttribute, ReflectUser = .All, AlwaysIncludeUser = .All)]
		struct BaseNamedAttribute : Attribute
		{
			public int32 mBaseValue;
			public int32 BaseAuto { get; set mut; }
		}

		[AttributeUsage(.Class | .Method | .Field | .Parameter, .ReflectAttribute, ReflectUser = .All, AlwaysIncludeUser = .All)]
		struct NamedAttribute : BaseNamedAttribute
		{
			public int32 mCtorArg;
			public int8 I8;
			public uint8 U8;
			public int16 I16;
			public uint16 U16;
			public int32 I32;
			public uint32 U32;
			public int64 I64;
			public uint64 U64;
			public int Int;
			public uint UInt;
			public char8 C8;
			public char16 C16;
			public char32 C32;
			public bool Flag;
			public float F;
			public double D;
			public SmallEnum Small;
			public WideEnum Wide;
			public PlainEnum Plain;
			public String Str;
			public Type Ty;
			public Object Boxed;
			public int32 Auto { get; set mut; }

			public this()
			{
				this = default;
				mCtorArg = -1;
				I32 = 100;
				Str = "ctor";
			}

			public this(int32 ctorArg)
			{
				this = default;
				mCtorArg = ctorArg;
				I32 = 100;
				Str = "ctor";
			}
		}

		[AttributeUsage(.Class | .Method | .Field | .Parameter, .ReflectAttribute, ReflectUser = .All, AlwaysIncludeUser = .All)]
		struct CtorOnlyAttribute : Attribute
		{
			public int32 mValue;
			public String mName;

			public this(int32 value, String name)
			{
				mValue = value;
				mName = name;
			}
		}

		[Reflect(.All), AlwaysInclude(AssumeInstantiated=true, IncludeAllMethods=true)]
		[CtorOnly(1, "first")]
		[Named(7, I8=-5, U8=250, I16=-300, U16=60000, I32=-70000, U32=4000000000, I64=-5000000000, U64=0xF000000000000001,
			Int=-6, UInt=7, C8='x', C16='\u{3A9}', C32='\u{1F600}', Flag=true, F=2.5f, D=-1.25, Small=.A, Wide=.Y, Plain=.Blue,
			Str="named", Ty=typeof(int16), Boxed=12, Auto=42, mBaseValue=9, BaseAuto=10)]
		[CtorOnly(2, "second")]
		class Target
		{
			[Named(I32=8), Named(3, Str=null)]
			public int mField;

			[Named(4, Plain=.Green)]
			public void Method([Named(5, Small=.B, Auto=-1)] int a, [CtorOnly(6, "param")] int b)
			{
			}
		}

		[Reflect(.All), AlwaysInclude(AssumeInstantiated=true)]
		[Named(11, Wide=.X)]
		class GenericTarget<T>
		{
		}

		static void CheckFull(NamedAttribute attr)
		{
			Test.Assert(attr.mCtorArg == 7);
			Test.Assert(attr.I8 == -5);
			Test.Assert(attr.U8 == 250);
			Test.Assert(attr.I16 == -300);
			Test.Assert(attr.U16 == 60000);
			Test.Assert(attr.I32 == -70000);
			Test.Assert(attr.U32 == 4000000000);
			Test.Assert(attr.I64 == -5000000000);
			Test.Assert(attr.U64 == 0xF000000000000001);
			Test.Assert(attr.Int == -6);
			Test.Assert(attr.UInt == 7);
			Test.Assert(attr.C8 == 'x');
			Test.Assert(attr.C16 == '\u{3A9}');
			Test.Assert(attr.C32 == '\u{1F600}');
			Test.Assert(attr.Flag);
			Test.Assert(attr.F == 2.5f);
			Test.Assert(attr.D == -1.25);
			Test.Assert(attr.Small == .A);
			Test.Assert(attr.Wide == .Y);
			Test.Assert(attr.Plain == .Blue);
			Test.Assert(attr.Str == "named");
			Test.Assert(attr.Ty == typeof(int16));
			Test.Assert((int)attr.Boxed == 12);
			Test.Assert(attr.Auto == 42);
			Test.Assert(attr.mBaseValue == 9);
			Test.Assert(attr.BaseAuto == 10);
		}

		[Test]
		public static void TestTypeAttribute()
		{
			CheckFull(typeof(Target).GetCustomAttribute<NamedAttribute>().Get());

			int namedCount = 0;
			int ctorOnlyCount = 0;
			for (let attr in typeof(Target).GetCustomAttributes())
			{
				if (attr.VariantType == typeof(NamedAttribute))
				{
					CheckFull(attr.Get<NamedAttribute>());
					namedCount++;
				}
				else if (attr.VariantType == typeof(CtorOnlyAttribute))
				{
					let ctorOnly = attr.Get<CtorOnlyAttribute>();
					Test.Assert(ctorOnly.mValue == ((ctorOnlyCount == 0) ? 1 : 2));
					Test.Assert(ctorOnly.mName == ((ctorOnlyCount == 0) ? "first" : "second"));
					ctorOnlyCount++;
				}
			}
			Test.Assert((namedCount == 1) && (ctorOnlyCount == 2));

			namedCount = 0;
			for (let attr in typeof(Target).GetCustomAttributes<NamedAttribute>())
			{
				CheckFull(attr);
				namedCount++;
			}
			Test.Assert(namedCount == 1);

			let ctorOnly = typeof(Target).GetCustomAttribute<CtorOnlyAttribute>().Get();
			Test.Assert((ctorOnly.mValue == 1) && (ctorOnly.mName == "first"));
		}

		[Test]
		public static void TestMemberAttributes()
		{
			let field = typeof(Target).GetField("mField").Get();
			let first = field.GetCustomAttribute<NamedAttribute>().Get();
			Test.Assert((first.mCtorArg == -1) && (first.I32 == 8) && (first.Str == "ctor"));

			int count = 0;
			for (let attr in field.GetCustomAttributes<NamedAttribute>())
			{
				if (count == 0)
					Test.Assert((attr.mCtorArg == -1) && (attr.I32 == 8) && (attr.Str == "ctor"));
				else
					Test.Assert((attr.mCtorArg == 3) && (attr.I32 == 100) && (attr.Str == null));
				count++;
			}
			Test.Assert(count == 2);

			bool foundMethod = false;
			for (let method in typeof(Target).GetMethods())
			{
				if (method.Name != "Method")
					continue;
				foundMethod = true;
				let methodAttr = method.GetCustomAttribute<NamedAttribute>().Get();
				Test.Assert((methodAttr.mCtorArg == 4) && (methodAttr.Plain == .Green) && (methodAttr.I32 == 100));

				let paramAttr = method.GetParamCustomAttribute<NamedAttribute>(0).Get();
				Test.Assert((paramAttr.mCtorArg == 5) && (paramAttr.Small == .B) && (paramAttr.Auto == -1));

				let ctorOnly = method.GetParamCustomAttribute<CtorOnlyAttribute>(1).Get();
				Test.Assert((ctorOnly.mValue == 6) && (ctorOnly.mName == "param"));
			}
			Test.Assert(foundMethod);

			let genericAttr = typeof(GenericTarget<int>).GetCustomAttribute<NamedAttribute>().Get();
			Test.Assert((genericAttr.mCtorArg == 11) && (genericAttr.Wide == .X) && (genericAttr.I32 == 100));
		}
	}
}
