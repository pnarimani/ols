package analysis

import "core:mem"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:strings"

import "src:common"

@(private = "package")
SymbolCollection :: struct {
	allocator:      mem.Allocator,
	config:         ^common.Config,
	packages:       map[string]SymbolPackage,
	intern:         strings.Intern,
}

ObjcFunction :: struct {
	physical_name: string,
	logical_name:  string,
}

ObjcStruct :: struct {
	functions: [dynamic]ObjcFunction,
	pkg:       string,
	ranges:    [dynamic]common.Range,
}

Method :: struct {
	pkg:  string,
	name: string,
}

@(private = "package")
SymbolPackage :: struct {
	symbols:            map[string]Symbol,
	objc_structs:       map[string]ObjcStruct, //mapping from struct name to function
	methods:            map[Method][dynamic]Symbol,
	imports:            [dynamic]string, //Used for references to figure whether the package is even able to reference the symbol
	proc_group_members: map[string]bool, // Tracks procedure names that are part of proc groups (used by fake methods)
}

// ============================================================================
// Symbol types
// ============================================================================

SymbolAndNode :: struct {
	symbol: Symbol,
	node:   ^ast.Node,
}

SymbolStructTag :: enum {
	Is_Packed,
	Is_Raw_Union,
	Is_No_Copy,
	Is_All_Or_None,
}

SymbolStructTags :: bit_set[SymbolStructTag]

SymbolStructValue :: struct {
	names:             []string,
	ranges:            []common.Range,
	types:             []^ast.Expr,
	usings:            []int,
	from_usings:       []int,
	unexpanded_usings: []int,
	poly:              ^ast.Field_List,
	poly_names:        []string, // The resolved names for the poly fields
	args:              []^ast.Expr, //The arguments in the call expression for poly
	docs:              []^ast.Comment_Group,
	comments:          []^ast.Comment_Group,
	where_clauses:     []^ast.Expr,

	// Extra fields for embedded bit fields via usings
	backing_types:     map[int]^ast.Expr, // the base type for the bit field
	bit_sizes:         map[int]^ast.Expr, // the bit size of the bit field field

	// Tag information
	align:             ^ast.Expr,
	min_field_align:   ^ast.Expr,
	max_field_align:   ^ast.Expr,
	tags:              SymbolStructTags,
}

symbol_struct_value_has_using :: proc(v: SymbolStructValue, index: int) -> bool {
	for u in v.usings {
		if u == index {
			return true
		}
	}
	return false
}

SymbolBitFieldValue :: struct {
	backing_type: ^ast.Expr,
	names:        []string,
	ranges:       []common.Range,
	types:        []^ast.Expr,
	docs:         []^ast.Comment_Group,
	comments:     []^ast.Comment_Group,
	bit_sizes:    []^ast.Expr,
}

SymbolPackageValue :: struct {}

SymbolProcedureValue :: struct {
	return_types:       []^ast.Field,
	arg_types:          []^ast.Field,
	orig_return_types:  []^ast.Field, //When generics have overloaded the types, we store the original version here.
	orig_arg_types:     []^ast.Field, //When generics have overloaded the types, we store the original version here.
	generic:            bool,
	diverging:          bool,
	calling_convention: ast.Proc_Calling_Convention,
	tags:               ast.Proc_Tags,
	attributes:         []^ast.Attribute,
	inlining:           ast.Proc_Inlining,
	where_clauses:      []^ast.Expr,
}

SymbolProcedureGroupValue :: struct {
	group: ^ast.Expr,
}

// currently only used for proc group references
// TODO needs a better name
SymbolAggregateValue :: struct {
	symbols: []Symbol,
}

SymbolEnumValue :: struct {
	names:     []string,
	values:    []^ast.Expr,
	base_type: ^ast.Expr,
	ranges:    []common.Range,
	docs:      []^ast.Comment_Group,
	comments:  []^ast.Comment_Group,
}

SymbolUnionValue :: struct {
	types:         []^ast.Expr,
	poly:          ^ast.Field_List,
	poly_names:    []string,
	docs:          []^ast.Comment_Group,
	comments:      []^ast.Comment_Group,
	kind:          ast.Union_Type_Kind,
	align:         ^ast.Expr,
	where_clauses: []^ast.Expr,
}

SymbolDynamicArrayValue :: struct {
	expr: ^ast.Expr,
}

SymbolMultiPointerValue :: struct {
	expr: ^ast.Expr,
}

SymbolFixedArrayValue :: struct {
	len:  ^ast.Expr,
	expr: ^ast.Expr,
}

SymbolSliceValue :: struct {
	expr: ^ast.Expr,
}

SymbolBasicValue :: struct {
	ident: ^ast.Ident,
}

SymbolBitSetValue :: struct {
	expr: ^ast.Expr,
}

SymbolUntypedValueType :: enum {
	Integer,
	Float,
	Complex,
	Quaternion,
	String,
	Bool,
}

SymbolUntypedValue :: struct {
	type: SymbolUntypedValueType,
	tok:  tokenizer.Token,
}

SymbolMapValue :: struct {
	key:   ^ast.Expr,
	value: ^ast.Expr,
}

SymbolMatrixValue :: struct {
	x:    ^ast.Expr,
	y:    ^ast.Expr,
	expr: ^ast.Expr,
}

SymbolPolyTypeValue :: struct {
	ident: ^ast.Ident,
}

/*
	Generic symbol that is used by the indexer for any variable type(constants, defined global variables, etc),
*/
SymbolGenericValue :: struct {
	expr:        ^ast.Expr,
	field_names: []string,
	ranges:      []common.Range,
}

SymbolValue :: union {
	SymbolStructValue,
	SymbolPackageValue,
	SymbolProcedureValue,
	SymbolGenericValue,
	SymbolProcedureGroupValue,
	SymbolUnionValue,
	SymbolEnumValue,
	SymbolBitSetValue,
	SymbolAggregateValue,
	SymbolDynamicArrayValue,
	SymbolFixedArrayValue,
	SymbolMultiPointerValue,
	SymbolMapValue,
	SymbolSliceValue,
	SymbolBasicValue,
	SymbolUntypedValue,
	SymbolMatrixValue,
	SymbolBitFieldValue,
	SymbolPolyTypeValue,
}

SymbolFlag :: enum {
	Builtin,
	Distinct,
	Deprecated,
	PrivateFile,
	PrivatePackage,
	Anonymous, //Usually applied to structs that are defined inline inside another struct
	Variable, // or type
	Mutable, // or constant
	Local,
	ObjC,
	ObjCIsClassMethod, // should be set true only when ObjC is enabled
	Soa,
	SoaPointer,
	Simd,
	Parameter, //If the symbol is a procedure argument
	PolyType,
}

SymbolFlags :: bit_set[SymbolFlag]

Symbol :: struct {
	range:       common.Range, //the range of the symbol in the file
	filepath:    string,
	pkg:         string, //absolute directory path where the symbol resides
	name:        string, //name of the symbol
	doc:         string,
	comment:     string,
	signature:   string, //type signature
	type:        SymbolType,
	parent_name: string, // When symbol is a field, this is the name of the parent symbol it is a field of
	type_pkg:    string,
	type_name:   string,
	value:       SymbolValue,
	pointers:    int, //how many `^` are applied to the symbol
	flags:       SymbolFlags,
	type_expr:   ^ast.Expr,
	value_expr:  ^ast.Expr,
}

SymbolType :: enum {
	Function      = 3,
	Field         = 5,
	Variable      = 6,
	Package       = 9,
	Enum          = 13,
	Keyword       = 14,
	EnumMember    = 20,
	Constant      = 21,
	Struct        = 22,
	Type_Function = 23,
	Union         = 7,
	Type          = 8, //For maps, arrays, slices, dyn arrays, matrixes, etc
	Unresolved    = 1, //Use text if not being able to resolve it.
}

SymbolStructValueBuilder :: struct {
	symbol:            Symbol,
	names:             [dynamic]string,
	types:             [dynamic]^ast.Expr,
	args:              [dynamic]^ast.Expr, //The arguments in the call expression for poly
	ranges:            [dynamic]common.Range,
	docs:              [dynamic]^ast.Comment_Group,
	comments:          [dynamic]^ast.Comment_Group,
	usings:            [dynamic]int,
	from_usings:       [dynamic]int,
	unexpanded_usings: [dynamic]int,
	poly:              ^ast.Field_List,
	poly_names:        [dynamic]string,
	where_clauses:     [dynamic]^ast.Expr,

	// Extra fields for embedded bit fields via usings
	backing_types:     map[int]^ast.Expr,
	bit_sizes:         map[int]^ast.Expr,

	// Tag information
	align:             ^ast.Expr,
	min_field_align:   ^ast.Expr,
	max_field_align:   ^ast.Expr,
	tags:              SymbolStructTags,
}

// ============================================================================
// SymbolStructValueBuilder constructors
// ============================================================================

import "core:slice"

symbol_struct_value_builder_make_none :: proc(allocator := context.allocator) -> SymbolStructValueBuilder {
	return SymbolStructValueBuilder {
		names = make([dynamic]string, allocator),
		types = make([dynamic]^ast.Expr, allocator),
		args = make([dynamic]^ast.Expr, allocator),
		ranges = make([dynamic]common.Range, allocator),
		docs = make([dynamic]^ast.Comment_Group, allocator),
		comments = make([dynamic]^ast.Comment_Group, allocator),
		usings = make([dynamic]int, allocator),
		from_usings = make([dynamic]int, allocator),
		unexpanded_usings = make([dynamic]int, allocator),
		poly_names = make([dynamic]string, allocator),
		backing_types = make(map[int]^ast.Expr, allocator),
		bit_sizes = make(map[int]^ast.Expr, allocator),
		where_clauses = make([dynamic]^ast.Expr, allocator),
	}
}

symbol_struct_value_builder_make_symbol :: proc(
	symbol: Symbol,
	allocator := context.allocator,
) -> SymbolStructValueBuilder {
	return SymbolStructValueBuilder {
		symbol = symbol,
		names = make([dynamic]string, allocator),
		types = make([dynamic]^ast.Expr, allocator),
		args = make([dynamic]^ast.Expr, allocator),
		ranges = make([dynamic]common.Range, allocator),
		docs = make([dynamic]^ast.Comment_Group, allocator),
		comments = make([dynamic]^ast.Comment_Group, allocator),
		usings = make([dynamic]int, allocator),
		from_usings = make([dynamic]int, allocator),
		unexpanded_usings = make([dynamic]int, allocator),
		poly_names = make([dynamic]string, allocator),
		backing_types = make(map[int]^ast.Expr, allocator),
		bit_sizes = make(map[int]^ast.Expr, allocator),
		where_clauses = make([dynamic]^ast.Expr, allocator),
	}
}

symbol_struct_value_builder_make_symbol_symbol_struct_value :: proc(
	symbol: Symbol,
	v: SymbolStructValue,
	allocator := context.allocator,
) -> SymbolStructValueBuilder {
	return SymbolStructValueBuilder {
		symbol = symbol,
		names = slice.to_dynamic(v.names, allocator),
		types = slice.to_dynamic(v.types, allocator),
		args = slice.to_dynamic(v.args, allocator),
		ranges = slice.to_dynamic(v.ranges, allocator),
		docs = slice.to_dynamic(v.docs, allocator),
		comments = slice.to_dynamic(v.comments, allocator),
		usings = slice.to_dynamic(v.usings, allocator),
		from_usings = slice.to_dynamic(v.from_usings, allocator),
		unexpanded_usings = slice.to_dynamic(v.unexpanded_usings, allocator),
		poly_names = slice.to_dynamic(v.poly_names, allocator),
		backing_types = v.backing_types,
		bit_sizes = v.bit_sizes,
		tags = v.tags,
		align = v.align,
		max_field_align = v.max_field_align,
		min_field_align = v.min_field_align,
		where_clauses = slice.to_dynamic(v.where_clauses, allocator),
	}
}

symbol_struct_value_builder_make :: proc {
	symbol_struct_value_builder_make_none,
	symbol_struct_value_builder_make_symbol,
	symbol_struct_value_builder_make_symbol_symbol_struct_value,
}

to_symbol :: proc(b: SymbolStructValueBuilder) -> Symbol {
	symbol := b.symbol
	symbol.value = to_symbol_struct_value(b)
	return symbol
}

to_symbol_struct_value :: proc(b: SymbolStructValueBuilder) -> SymbolStructValue {
	return SymbolStructValue {
		names = b.names[:],
		types = b.types[:],
		ranges = b.ranges[:],
		args = b.args[:],
		docs = b.docs[:],
		comments = b.comments[:],
		usings = b.usings[:],
		from_usings = b.from_usings[:],
		unexpanded_usings = b.unexpanded_usings[:],
		poly = b.poly,
		poly_names = b.poly_names[:],
		backing_types = b.backing_types,
		bit_sizes = b.bit_sizes,
		align = b.align,
		max_field_align = b.max_field_align,
		min_field_align = b.min_field_align,
		tags = b.tags,
		where_clauses = b.where_clauses[:],
	}
}
