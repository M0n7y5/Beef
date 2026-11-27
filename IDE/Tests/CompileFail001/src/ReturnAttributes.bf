using System;

namespace IDETest
{
	class ReturnAttributes
	{
		[AttributeUsage(.Field)]
		struct FieldOnlyAttribute : Attribute
		{
		}

		[AttributeUsage(.ReturnValue)]
		struct ReturnOnlyAttribute : Attribute
		{
		}

		[return: FieldOnly] //FAIL only valid on field declarations
		public static int Wrong() => 0;

		[return: ReturnOnly]
		public static int Right() => 0;
	}
}
