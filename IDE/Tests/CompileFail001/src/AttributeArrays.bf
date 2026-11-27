using System;
using System.Reflection;

namespace IDETest
{
	class AttributeArrays
	{
		[AttributeUsage(.Method)]
		struct StoredListAttribute : Attribute
		{
			public int32[] mItems;

			public this(params int32[] items)
			{
				mItems = items;
			}
		}

		[AttributeUsage(.Method)]
		struct SumAttribute : Attribute
		{
			public int32 mSum;

			public this(params int32[] items)
			{
				mSum = 0;
				for (let item in items)
					mSum += item;
			}
		}

		struct Target
		{
			[StoredList(1, 2, 3)] //FAIL holds a 'int32[]' reference
			public void Stored()
			{
			}

			[Sum(1, 2, 3)]
			public void Summed()
			{
			}
		}

		static class Reader
		{
			[OnCompile(.TypeInit), Comptime]
			static void Generate()
			{
				int32 sum = 0;
				for (let method in typeof(Target).GetMethods())
				{
					if (method.GetCustomAttribute<StoredListAttribute>() case .Ok(let stored))
						sum += (stored.mItems == null) ? 0 : 1;
					if (method.GetCustomAttribute<SumAttribute>() case .Ok(let summed))
						sum += summed.mSum;
				}
				Compiler.EmitTypeBody(typeof(Self), scope $"public const int32 cSum = {sum};\n");
			}
		}
	}
}
