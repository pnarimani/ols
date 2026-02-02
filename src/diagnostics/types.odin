package diagnostics

import "src:common"

DiagnosticType :: enum {
	Syntax,
	Unused,
	Check,
	Hint,
}

DiagnosticSeverity :: enum {
	Error       = 1,
	Warning     = 2,
	Information = 3,
	Hint        = 4,
}

DiagnosticTag :: enum int {
	Unnecessary = 1,
	Deprecated  = 2,
}

Diagnostic :: struct {
	range:    common.Range,
	severity: DiagnosticSeverity,
	code:     string,
	message:  string,
	tags:     [1]DiagnosticTag,
}
