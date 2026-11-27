using System;
using System.Reflection;

namespace Tests
{
	class ReturnAttributes
	{
		[AttributeUsage(.ReturnValue, .ReflectAttribute)]
		struct RetAttribute : Attribute
		{
			public int32 mValue;

			public this(int32 value)
			{
				mValue = value;
			}
		}

		[AttributeUsage(.Method, .ReflectAttribute)]
		struct MarkAttribute : Attribute
		{
		}

		[Reflect(.Methods), AlwaysInclude(IncludeAllMethods=true)]
		struct Target
		{
			[return: Ret(7)]
			public int32 Alone() => 0;

			[Mark, return: Ret(8)]
			public int32 SameBlock() => 0;

			[Mark]
			[return: Ret(9)]
			public int32 OwnBlock() => 0;

			[Mark]
			public int32 None() => 0;
		}

		static int32 ReturnValue(StringView methodName)
		{
			let method = typeof(Target).GetMethod(methodName).Value;
			int count = 0;
			for (let attr in method.GetReturnCustomAttributes())
				count++;
			for (let attr in method.GetReturnCustomAttributes<RetAttribute>())
				count++;
			if (method.GetReturnCustomAttribute<RetAttribute>() case .Ok(let attr))
				return (count == 2) ? attr.mValue : -1;
			return (count == 0) ? 0 : -1;
		}

		[Test]
		public static void TestReturnAttributes()
		{
			Test.Assert(ReturnValue("Alone") == 7);
			Test.Assert(ReturnValue("SameBlock") == 8);
			Test.Assert(ReturnValue("OwnBlock") == 9);
			Test.Assert(ReturnValue("None") == 0);
			Test.Assert(typeof(Target).GetMethod("SameBlock").Value.GetCustomAttribute<MarkAttribute>() case .Ok);
		}
	}
}
