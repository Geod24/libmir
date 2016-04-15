/++
$(H2 Sparse Tensors)

This is a submodule of $(LINK2 mir_ndslice.html, mir.ndslice).


License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).

Authors:   Ilya Yaroshenko

Source:    $(PHOBOSSRC std/_experimental/_ndslice/_sparse.d)

Macros:
SUBMODULE = $(LINK2 mir_ndslice_$1.html, mir.ndslice.$1)
SUBREF = $(LINK2 mir_ndslice_$1.html#.$2, $(TT $2))$(NBSP)
T2=$(TR $(TDNW $(LREF $1)) $(TD $+))
T4=$(TR $(TDNW $(LREF $1)) $(TD $2) $(TD $3) $(TD $4))

+/
module mir.ndslice.sparse;

import std.traits;
import std.meta;

import mir.ndslice.internal;
import mir.ndslice.slice;

/++
Sparse tensors represented in Dictionary of Keys (DOK) format.

Params:
    N = dimension count
    lengths = list of dimension lengths
Returns:
    `N`-dimensional slice composed of indexes
See_also: $(LREF Sparse)
+/
Sparse!(Lengths.length, T) sparse(T, Lengths...)(Lengths lengths)
    if (allSatisfy!(isIndex, Lengths))
{
    return .sparse!(T, Lengths.length)([lengths]);
}

/// ditto
Sparse!(N, T) sparse(T, size_t N)(auto ref size_t[N] lengths)
{
    import mir.ndslice.slice: sliced;
    T[size_t] table;
    table[0] = 0;
    table.remove(0);
    assert(table !is null);
    with (typeof(return)) return SparseMap!T(table).sliced(lengths);
}

///
pure unittest
{
    auto slice = sparse!double(2, 3);
    slice[0][] = 1;
    slice[0, 1] = 2;
    --slice[0, 0];
    slice[1, 2] += 4;

    assert(slice == [[0, 2, 1], [0, 0, 4]]);

    import std.range.primitives: isRandomAccessRange;
    static assert(isRandomAccessRange!(Sparse!(2, double)));

	import mir.ndslice.slice: Slice, DeepElementType;
    static assert(is(Sparse!(2, double) : Slice!(2, Range), Range));
    static assert(is(DeepElementType!(Sparse!(2, double)) == double));
}

/++
Sparse Slice in Dictionary of Keys Format.
+/
template Sparse(size_t N, T)
	if(N)
{
	alias Sparse = Slice!(N, SparseMap!T);
}

// undocumented
struct SparseMap(T)
{
	T[size_t] table;

	auto save()
	{
		return this;
	}

	T opIndex(size_t index)
	{
		static if (isScalarType!T)
			return table.get(index, cast(T)0);
		else
			return table.get(index, null);
	}

	T opIndexAssign(T value, size_t index)
	{
		static if (isScalarType!T)
		{
			if (value != 0)
			{
				table[index] = value;
			}
		}
		else
		{
			if (value !is null)
			{
				table[index] = value;
			}
		}
		return value;
	}

	T opIndexUnary(string op)(size_t index)
		if (op == `++` || op == `--`)
	{
		mixin (`auto value = ` ~ op ~ `table[index];`);
		static if (isScalarType!T)
		{
			if (value == 0)
			{
				table.remove(index);
			}
		}
		else
		{
			if (value is null)
			{
				table.remove(index);
			}
		}
		return value;
 	}

	T opIndexOpAssign(string op)(T value, size_t index)
		if (op == `+` || op == `-`)
	{
		mixin (`value = table[index] ` ~ op ~ `= value;`); // this works
		static if (isScalarType!T)
		{
			if (value == 0)
			{
				table.remove(index);
			}
		}
		else
		{
			if (value is null)
			{
				table.remove(index);
			}
		}
		return value;
    }
}

/++
+/
struct CoordinateValue(size_t N, T)
{
	///
	size_t[N] index;
	
	///
	T value;

	///
	sizediff_t opCmp()(auto ref const typeof(this) rht) const
	{
		return cmpCoo(this.index, rht.index);
	}
}

private sizediff_t cmpCoo(size_t N)(const auto ref size_t[N] a, const auto ref size_t[N] b)
{
	foreach(i; Iota!(0, N))
		if(auto d = a[i] - b[i])
			return d;
	return 0;
}

/++
+/
auto byCoordinateValue(S : Slice!(N, R), size_t N, R : SparseMap!T, T)(S slice)
{
	static struct CoordinateValues
	{
		static if(N > 1)
			private sizediff_t[N-1] _strides;
		mixin _sparse_range_methods!(N, T);
		private typeof(Sparse!(N, T).init._ptr._range.table.byKeyValue()) _range;

		auto front() @property
		{
			assert(!_range.empty);
			auto iv = _range.front;
			size_t index = iv.key;
			CoordinateValue!(N, T) ret = void;
			foreach(i; Iota!(0, N - 1))
			{
				ret.index[i] = index / _strides[i];
				index %= _strides[i];
			}
			ret.index[N - 1] = index;
			ret.value = iv.value;
			return ret;
		}

		//int opApply(Dg)(scope Dg dg)
		//	if (ParameterTypeTuple!Dg.length == N + 1 && allSatisfy!(isIndex, ParameterTypeTuple!Dg[0..N]))
		//{
		//	int result = 0;
		//	foreach(coov; this.save)
		//	{
		//		ParameterTypeTuple!Dg[0..N] coo = void;
		//		foreach(i, ref c; coo)
		//			c = cast(ParameterTypeTuple!Dg[i]) coov.index[i];
		//		result = dg(coo, coov.value);
		//		if (result)
		//			break;
		//	}
		//	return result;
		//}
	}
	static if(N > 1)
	{
		CoordinateValues ret = void;
		ret._strides = slice._strides[0..N-1];
		ret._length = slice._ptr._range.table.length;
		ret._range = slice._ptr._range.table.byKeyValue;
		return ret;
	}
	else
		return CoordinateValues(slice._ptr._range.table.byKeyValue);
}

///
pure unittest
{
	import std.array: array;
	import std.algorithm.sorting: sort;
	alias CV = CoordinateValue!(2, double);

	auto slice = sparse!double(3, 3);
	slice[] = [[0, 2, 1], [0, 0, 4], [6, 7, 0]];
	assert(slice.byCoordinateValue.array.sort().release == [
		CV([0, 1], 2),
		CV([0, 2], 1),
		CV([1, 2], 4),
		CV([2, 0], 6),
		CV([2, 1], 7)]);
}

/++
+/
auto byCoordinate(S : Slice!(N, R), size_t N, R : SparseMap!T, T)(S slice)
{
	static struct Coordinates
	{
		static if(N > 1)
			private sizediff_t[N-1] _strides;
		mixin _sparse_range_methods!(N, T);
		private typeof(Sparse!(N, T).init._ptr._range.table.byKey()) _range;

		auto front() @property
		{
			assert(!_range.empty);
			size_t index = _range.front;
			size_t[N] ret = void;
			foreach(i; Iota!(0, N - 1))
			{
				ret[i] = index / _strides[i];
				index %= _strides[i];
			}
			ret[N - 1] = index;
			return ret;
		}
	}
	static if(N > 1)
	{
		Coordinates ret = void;
		ret._strides = slice._strides[0..N-1];
		ret._length = slice._ptr._range.table.length;
		ret._range = slice._ptr._range.table.byKey;
		return ret;
	}
	else
		return Coordinates(slice._ptr._range.table.byKey);
}

///
pure unittest
{
	import std.array: array;
	import std.algorithm.sorting: sort;
	alias CV = CoordinateValue!(2, double);

	auto slice = sparse!double(3, 3);
	slice[] = [[0, 2, 1], [0, 0, 4], [6, 7, 0]];
	assert(slice.byCoordinate.array.sort().release == [
		[0, 1],
		[0, 2],
		[1, 2],
		[2, 0],
		[2, 1]]);
}

/++
+/
auto byValueOnly(S : Slice!(N, R), size_t N, R : SparseMap!T, T)(S slice)
{
	static struct Values
	{
		mixin _sparse_range_methods!(N, T);
		private typeof(Sparse!(N, T).init._ptr._range.table.byValue) _range;

		auto front() @property
		{
			assert(!_range.empty);
			return _range.front;
		}
	}
	return Values(slice._ptr._range.table.length, slice._ptr._range.table.byValue);
}

///
pure unittest
{
	import std.array: array;
	import std.algorithm.sorting: sort;

	auto slice = sparse!double(3, 3);
	slice[] = [[0, 2, 1], [0, 0, 4], [6, 7, 0]];
	assert(slice.byValueOnly.array.sort().release == [1, 2, 4, 6, 7]);
}

private mixin template _sparse_range_methods(size_t N, T)
{
	private size_t _length;

	void popFront()
	{
		assert(!_range.empty);
		_range.popFront;
		_length--;
	}

	bool empty() const @property
	{
		return _length == 0;
	}

	auto save() @property
	{
		return _range.save;
	}

	size_t length() const @property
	{
		return _length;
	}
}

CompressedTensor!(N - 1, T, I, J)
	compress
	(I = uint, J = uint, S : Slice!(N, R), size_t N, R : SparseMap!T, T)
	(S slice)
	if(N > 1)
{
	return compressTo!T(slice);
}

CompressedTensor!(N - 1, V, I, J)
	compressTo
	(V, I = uint, J = uint, S : Slice!(N, R), size_t N, R : SparseMap!T, T)
	(S slice)
	if(is(T : V) && N > 1)
{
	import std.array: array;
	import std.algorithm.sorting: sort;
	import mir.ndslice.selection: iotaSlice;
	auto data = slice
		._ptr
		._range
		.table
		.byKeyValue
		.array
		.sort!((a, b) => a.key < b.key)
		.release;
	auto inv = iotaSlice(slice.shape[0 .. N - 1]);
	auto count = inv.elementsCount;
	auto map = CompressedMap!(V, I, J)(
		slice.length!(N - 1),
		new V[data.length],
		new I[data.length],
		new J[count + 1],
		);
	size_t k = 0;
	map.pointers[0] = 0;
	map.pointers[1] = 0;
	foreach(t, e; data)
	{
		map.values[t] = cast(V) e.value;
		size_t index = e.key;
		map.indexes[t] = cast(I)(index % slice.length!(N - 1));
		auto p = index / slice.length!(N - 1);
		if(k != p)
		{
			map.pointers[k + 2 .. p + 2] = map.pointers[k + 1];
			k = p;
		}
		map.pointers[k + 1]++;
	}
	return map.sliced(inv.shape);
}

unittest
{
	import std.array: array;
	import std.algorithm.sorting: sort;
	alias CV = CoordinateValue!(2, double);

	auto sparse = sparse!double(5, 3);
	sparse[] =
		[[0, 2, 1],
		 [0, 0, 4],
		 [0, 0, 0],
		 [6, 0, 9],
		 [0, 0, 5]];

	auto crs = sparse.compress;
	assert(crs._ptr._range == CompressedMap!(double, uint, uint)(
		 3,
		[2, 1, 4, 6, 9, 5],
		[1, 2, 2, 0, 2, 2],
		[0, 2, 3, 3, 5, 6]));
}

alias CompressedTensor(size_t N, T, I = uint, J = uint) = Slice!(N, CompressedMap!(T, I, J));

/++
+/
struct CompressedArray(T, I = uint)
	if (is(I : size_t) && isUnsigned!I)
{
	/++
	+/
	T[] values;

	/++
	+/
	I[] indexes;
}

/++
+/
struct CompressedMap(T, I, J)
	if (is(I : size_t) && isUnsigned!I && is(J : size_t) && isUnsigned!J && I.sizeof <= J.sizeof)
{
	/++
	+/
	size_t compressedLength;

	/++
	+/
	T[] values;

	/++
	+/
	I[] indexes;

	/++
	+/
	J[] pointers;

	/++
	+/
	inout(CompressedArray!(T, I)) opIndex(size_t index) inout
	in
	{
		assert(index < pointers.length - 1);
	}
	body
	{
		auto a = pointers[index];
		auto b = pointers[index + 1];
		return typeof(return)(values[a .. b], indexes[a .. b]);
	}
}
