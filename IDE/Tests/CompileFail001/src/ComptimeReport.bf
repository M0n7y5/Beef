using System;
using System.Reflection;

namespace IDETest
{
	class ComptimeReport
	{
		[AttributeUsage(.Class)]
		struct RefuseAttribute : Attribute, IComptimeTypeApply
		{
			[Comptime]
			public void ApplyToType(Type type)
			{
				Compiler.Error(type, "Refused by its attribute");
			}
		}

		[AttributeUsage(.Class)]
		struct CautionAttribute : Attribute, IComptimeTypeApply
		{
			[Comptime]
			public void ApplyToType(Type type)
			{
				Compiler.Warn(type, "Caution from its attribute");
				Compiler.Error(type.GetField("mBad").Value, "Field refused");
			}
		}

		[AttributeUsage(.Method)]
		struct MethodCheckAttribute : Attribute, IComptimeMethodApply
		{
			[Comptime]
			public void ApplyToMethod(MethodInfo method)
			{
				Compiler.Error(method, "Method refused");
			}
		}

		[Refuse]
		class Refused //FAIL Refused by its attribute
		{
		}

		[Caution]
		class Cautioned //WARN Caution from its attribute
		{
			public int mBad; //FAIL Field refused
		}

		class Methods
		{
			[MethodCheck]
			public void Checked() //FAIL Method refused
			{
			}
		}
	}
}
