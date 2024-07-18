using System.Globalization;

namespace System
{
#unwarn
	struct Int64 : int64, IInteger, ISigned, IFormattable, IHashable, IIsNaN, IParseable<int64, ParseError>, IParseable<int64>, IMinMaxValue<int64>
	{
		public enum ParseError
		{
			case Ok;
			case NoValue;
			case Overflow;
			case InvalidChar(int64 partialResult);
		}

		public const int64 MaxValue = 0x7FFFFFFFFFFFFFFFL;
		public const int64 MinValue = -0x8000000000000000L;

		public static int64 IMinMaxValue<int64>.MinValue => MinValue;
		public static int64 IMinMaxValue<int64>.MaxValue => MaxValue;

		public static int operator<=>(Int64 a, Int64 b)
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

		public static Int64 operator-(Int64 value)
		{
			return -(SelfBase)value;
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
			return (int)(int64)this;
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
			if(format == null || format.IsEmpty)
			{
				ToString(outString);
			}
			else
			{
				NumberFormatter.NumberToString(format, (int64)this, formatProvider, outString);
			}
		}

		public override void ToString(String strBuffer)
		{
			// Dumb, make better.
			char8[] strChars = scope:: char8[22];
			int32 char8Idx = 20;
			int64 valLeft = (int64)this;
			bool isNeg = true;
			int minNumeralsLeft = 0;
			if (valLeft >= 0)
			{
				valLeft = -valLeft;
				isNeg = false;
			}
			while ((valLeft < 0) || (minNumeralsLeft > 0))
			{
				strChars[char8Idx] = (char8)('0' &- (valLeft % 10));
				valLeft /= 10;
				char8Idx--;
				minNumeralsLeft--;
			}
			if (char8Idx == 20)
				strChars[char8Idx--] = '0';
			if (isNeg)
				strChars[char8Idx--] = '-';
			char8* char8Ptr = &strChars[char8Idx + 1];
			strBuffer.Append(char8Ptr);
		}

		public static Result<int64, ParseError> Parse(StringView val, NumberStyles style = .Number, CultureInfo cultureInfo = null)
		{
			//TODO: Use Number.ParseNumber

			if (val.IsEmpty)
				return .Err(.NoValue);

			bool isNeg = false;
			bool digitsFound = false;
			int64 result = 0;

			int64 radix = style.HasFlag(.Hex) ? 0x10 : 10;

			for (int32 i = 0; i < val.Length; i++)
			{
				char8 c = val[i];

				if ((i == 0) && (c == '-'))
				{
					isNeg = true;
					continue;
				}

				if ((c >= '0') && (c <= '9'))
				{
					result &*= radix;
					result &+= (int64)(c - '0');
					digitsFound = true;
				}
				else if ((c >= 'a') && (c <= 'f'))
				{
					if (radix != 0x10)
						return .Err(.InvalidChar(result));
					result &*= radix;
					result &+= c - 'a' + 10;
					digitsFound = true;
				}
				else if ((c >= 'A') && (c <= 'F'))
				{
					if (radix != 0x10)
						return .Err(.InvalidChar(result));
					result &*= radix;
					result &+= c - 'A' + 10;
					digitsFound = true;
				}
				else if ((c == 'X') || (c == 'x'))
				{
					if ((!style.HasFlag(.AllowHexSpecifier)) || (i == 0) || (result != 0))
						return .Err(.InvalidChar(result));
					radix = 0x10;
					digitsFound = false;
				}
				else if (c == '\'')
				{
					// Ignore
				}
				else if ((c == '+') && (i == 0))
				{
					// Ignore
				}
				else
					return .Err(.InvalidChar(result));

				if (isNeg ? (uint64)result > (uint64)MinValue : (uint64)result > (uint64)MaxValue)
					return .Err(.Overflow);
			}

			if (!digitsFound)
				return .Err(.NoValue);

			return isNeg ? -result : result;
		}

		public static Result<int64, ParseError> IParseable<int64, ParseError>.Parse(StringView val)
		{
			return Parse(val);
		}

		public static Result<int64> IParseable<int64>.Parse(StringView val)
		{
			var res = Parse(val);
			if(res case .Err)
				return .Err;
			else
				return .Ok(res.Value);
		}
	}
}
