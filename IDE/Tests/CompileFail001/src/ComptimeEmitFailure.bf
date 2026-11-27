using System;

namespace IDETest
{
	class ComptimeEmitFailure
	{
		interface IEmitted
		{
		}

		interface IDeclared
		{
		}

		[AttributeUsage(.Struct)]
		struct FailAfterAddAttribute : Attribute, IComptimeTypeApply
		{
			[Comptime]
			public void ApplyToType(Type type)
			{
				Compiler.EmitAddInterface(type, typeof(IEmitted));
				Runtime.FatalError("Refused");
			}
		}

		[AttributeUsage(.Struct)]
		struct FailAttribute : Attribute, IComptimeTypeApply
		{
			[Comptime]
			public void ApplyToType(Type type)
			{
				Runtime.FatalError("Refused");
			}
		}

		[FailAfterAdd] //FAIL
		struct EmittedInterface
		{
			public int32 mA;
		}

		[Fail] //FAIL
		struct DeclaredInterface : IDeclared
		{
			public int32 mA;
		}

		static void NeedEmitted<T>(T value) where T : IEmitted
		{
		}

		static void NeedDeclared<T>(T value) where T : IDeclared
		{
		}

		static void Use()
		{
			NeedEmitted(EmittedInterface());
			NeedDeclared(DeclaredInterface());
		}
	}
}
