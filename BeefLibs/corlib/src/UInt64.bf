using System.Globalization;

namespace System
{
#unwarn
	struct UInt64 : uint64, IInteger, IUnsigned, IHashable, IIsNaN, IFormattable, IParseable<uint64, ParseError>, IParseable<uint64>, IMinMaxValue<uint64>
	{
		public enum ParseError
		{
			case Ok;
			case NoValue;
			case Overflow;
			case InvalidChar(uint64 partialResult);
		}

		public const uint64 MaxValue = 0xFFFFFFFFFFFFFFFFUL;
		public const uint64 MinValue = 0;

		public static uint64 IMinMaxValue<uint64>.MinValue => MinValue;
		public static uint64 IMinMaxValue<uint64>.MaxValue => MaxValue;

		public static int operator<=>(UInt64 a, UInt64 b)
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
			if(format == null || format.IsEmpty)
			{
				ToString(outString);
			}
			else
			{
				NumberFormatter.NumberToString(format, (uint64)this, formatProvider, outString);
			}
		}

		public override void ToString(String strBuffer)
		{
		    // Dumb, make better.
		    char8[] strChars = scope:: char8[22];
		    int32 char8Idx = 20;
		    uint64 valLeft = (uint64)this;
		    while (valLeft > 0)
		    {
		        strChars[char8Idx] = (char8)('0' + (valLeft % 10));
		        valLeft /= 10;
		        char8Idx--;
			}
		    if (char8Idx == 20)
		        strChars[char8Idx--] = '0';
		    char8* char8Ptr = &strChars[char8Idx + 1];
		    strBuffer.Append(char8Ptr);
		}

		public static Result<uint64, ParseError> Parse(StringView val, NumberStyles style = .Number, CultureInfo cultureInfo = null)
		{
			//TODO: Use Number.ParseNumber

			if (val.IsEmpty)
				return .Err(.NoValue);

			bool digitsFound = false;
			uint64 result = 0;
			uint64 prevResult = 0;

			uint64 radix = style.HasFlag(.Hex) ? 0x10 : 10;

			for (int32 i = 0; i < val.Length; i++)
			{
				char8 c = val[i];

				if ((c >= '0') && (c <= '9'))
				{
					result &*= radix;
					result &+= (uint64)(c - '0');
					digitsFound = true;
				}
				else if ((c >= 'a') && (c <= 'f'))
				{
					if (radix != 0x10)
						return .Err(.InvalidChar(result));
					result &*= radix;
					result &+= (uint64)(c - 'a' + 10);
					digitsFound = true;
				}
				else if ((c >= 'A') && (c <= 'F'))
				{
					if (radix != 0x10)
						return .Err(.InvalidChar(result));
					result &*= radix;
					result &+= (uint64)(c - 'A' + 10);
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

				if (result < prevResult)
					return .Err(.Overflow);
				prevResult = result;
			}

			if (!digitsFound)
				return .Err(.NoValue);

			return result;
		}

		public static Result<uint64, ParseError> IParseable<uint64, ParseError>.Parse(StringView val)
		{
			return Parse(val);
		}

		public static Result<uint64> IParseable<uint64>.Parse(StringView val)
		{
			var res = Parse(val);
			if(res case .Err)
				return .Err;
			else
				return .Ok(res.Value);
		}
	}
}
