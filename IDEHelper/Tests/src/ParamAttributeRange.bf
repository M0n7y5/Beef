using System;
using System.Reflection;

namespace Tests
{
	class ParamAttributeRange
	{
		[AttributeUsage(.Parameter, .ReflectAttribute)]
		struct TagAttribute : Attribute
		{
		}

		[Reflect(.Methods), AlwaysInclude(IncludeAllMethods=true)]
		struct Target
		{
			public void Call([Tag] int32 a)
			{
			}
		}

		[Test]
		public static void TestOutOfRangeIndex()
		{
			let method = typeof(Target).GetMethod("Call").Value;
			Test.Assert(method.GetParamCustomAttribute<TagAttribute>(0) case .Ok);

			int[3] outOfRange = .(1, -1, int.MaxValue);
			for (let paramIdx in outOfRange)
			{
				Test.Assert(method.GetParamCustomAttribute<TagAttribute>(paramIdx) case .Err);

				int count = 0;
				for (let attr in method.GetParamCustomAttributes(paramIdx))
					count++;
				for (let attr in method.GetParamCustomAttributes<TagAttribute>(paramIdx))
					count++;
				Test.Assert(count == 0);
			}
		}
	}
}
