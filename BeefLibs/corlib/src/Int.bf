using System;

namespace System
{
#unwarn
	struct Int : int, IInteger, IHashable, IFormattable, IIsNaN, IParseable<int, ParseError>, IParseable<int>, IMinMaxValue<int>
    {
		public enum ParseError
		{
			case Ok;
			case NoValue;
			case Overflow;
			case InvalidChar(int partialResult);
		}

		public struct Simple : int
		{
			public override void ToString(String strBuffer)
			{
				((int)this).ToString(strBuffer);
			}
		}

		public const int MaxValue = (sizeof(int) == 8) ? 0x7FFFFFFFFFFFFFFFL : 0x7FFFFFFF;
		public const int MinValue = (sizeof(int) == 8) ? -0x8000000000000000L : -0x80000000;

		public static int IMinMaxValue<int>.MinValue => MinValue;
		public static int IMinMaxValue<int>.MaxValue => MaxValue;

		public static int operator<=>(Self a, Self b)
		{
			return (SelfBase)a <=> (SelfBase)b;
		}

		public static Self operator+(Self lhs, Self rhs)
		{
			return (SelfBase)lhs + (SelfBase)rhs;
		}

		public static Self operator-(Self lhs, Self rhs)
		{
			return (SelfBase)lhs - (SelfBase)rhs;
		}

		public static Self operator-(Self value)
		{
			return (SelfBase)value;
		}

		public static Self operator*(Self lhs, Self rhs)
		{
			return (SelfBase)lhs * (SelfBase)rhs;
		}

		public static Self operator/(Self lhs, Self rhs)
		{
			return (SelfBase)lhs / (SelfBase)rhs;
		}

		public int GetHashCode()
		{
			return (int)this;
		}

		bool IIsNaN.IsNaN
		{
			[SkipCall]
			get
			{
				return false;
			}
		}

		public void ToString(String outString, String format, IFormatProvider formatProvider)
		{								   
			if (sizeof(int) == sizeof(int64))
			{
				((int64)this).ToString(outString, format, formatProvider);
			}
			else
			{
				((int32)this).ToString(outString, format, formatProvider);
			}
		}

		public override void ToString(String outString)
		{
			if (sizeof(int) == sizeof(int64))
			{
				((int64)this).ToString(outString);
			}
			else
			{
				((int32)this).ToString(outString);
			}
		}

		public static Result<int, ParseError> Parse(StringView val)
		{
			if (sizeof(Self) == sizeof(int64))
			{
				var result = Int64.Parse(val);
				return *(Result<int, ParseError>*)&result;
			}
			else
			{
				var result = Int32.Parse(val);
				return *(Result<int, ParseError>*)&result;
			}
		}

		public static Result<int, ParseError> IParseable<int, ParseError>.Parse(StringView val)
		{
			return Parse(val);
		}

		public static Result<int> IParseable<int>.Parse(StringView val)
		{
			var res = Parse(val);
			if(res case .Err)
				return .Err;
			else
				return .Ok(res.Value);
		}
	}
}
