# This script swaps the parameter order in expect_code_action_diff calls
# From: test.expect_code_action_diff(t, `...`, ACTION_NAME,)
# To:   test.expect_code_action_diff(t, ACTION_NAME, `...`,)

$files = @(
    "c:\dev\ols\tests\action_extract_proc_test.odin",
    "c:\dev\ols\tests\action_extract_variable_test.odin",
    "c:\dev\ols\tests\action_inline_proc_test.odin",
    "c:\dev\ols\tests\action_inline_variable_test.odin"
)

foreach ($file in $files) {
    Write-Host "Processing $file..."
    $content = Get-Content $file -Raw
    
    # Pattern explanation:
    # (test\.expect_code_action_diff\(\s*t,\s*)  - Capture the function call and 't,' parameter
    # (`(?:[^`]|``)*`,\s*)                       - Capture the diff source (backtick string) with comma
    # ([A-Z_]+_ACTION,)                          - Capture the action name constant
    
    $pattern = '(test\.expect_code_action_diff\(\s*t,\s*)(`(?:[^`]|``)*`,\s*)([A-Z_]+_ACTION,)'
    $newContent = $content -replace $pattern, '$1$3 $2'
    
    if ($content -ne $newContent) {
        Set-Content $file $newContent -NoNewline
        Write-Host "  Updated successfully"
    } else {
        Write-Host "  No changes needed"
    }
}

Write-Host "Done!"
