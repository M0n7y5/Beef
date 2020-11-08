using System.Reflection;

namespace System
{
	struct Enum
	{
		public static void EnumToString(Type type, String strBuffer, int64 iVal)
		{
			for (var field in type.GetFields())
			{
				if (field.[Friend]mFieldData.[Friend]mData == iVal)
				{
					strBuffer.Append(field.Name);
					return;
				}
			}

			((int32)iVal).ToString(strBuffer);
		}

		public static void EnumToString<T>(String strBuffer, T val) where T : Enum
		{
			let type = typeof(T);
			for (var field in type.GetFields())
			{
				if (field.[Friend]mFieldData.[Friend]mData == (.)val)
				{
					strBuffer.Append(field.Name);
					return;
				}
			}
		}

		public static Result<T> Parse<T>(StringView str, bool ignoreCase = false) where T : Enum
		{
			var typeInst = (TypeInstance)typeof(T);
			for (var field in typeInst.GetFields())
			{
				if (str.Equals(field.[Friend]mFieldData.mName, ignoreCase))
					return .Ok(*((T*)(&field.[Friend]mFieldData.mData)));
			}

			return .Err;
		}

		/*public override void ToString(String strBuffer) mut
		{
			Type type = GetType();
			int32* iPtr = (int32*)((int)(&this) + (int)type.Size);
			EnumToString(type, strBuffer, *iPtr);
			//EnumToString(GetType(), )
		}*/
	}
}
