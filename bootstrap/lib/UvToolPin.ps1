# =============================================================================
#  UvToolPin.ps1  (dot-source it)
#
#  Part of pins (Sync-Pins.ps1): how pins recognises a uv tool already at its
#  pin. Kept in its own file so Pester and tests/uvtools-smoke.sh can call it;
#  the smoke test checks it against the listing the real uv prints, which the
#  sandbox suites (fake uvs) never see.
#
#    Test-NowhereUvToolPinned -Spec <spec> -Listed <lines>
#      does `uv tool list --show-version-specifiers` output show this exact pin?
#        name @ source   a "name v..." line containing " <source>]"
#        name==version   a "name v<version>" line
#
#  The Linux counterpart is uvtool-pin.sh, with the same rule.
# =============================================================================

function Test-NowhereUvToolPinned {
    param(
        [Parameter(Mandatory)] [string]$Spec,
        [AllowNull()] [AllowEmptyCollection()] [string[]]$Listed = @()
    )
    if ($Spec -like '* @ *') {
        $name, $source = $Spec -split ' @ ', 2
        $hits = @($Listed | Where-Object { $_ -match ('^' + [regex]::Escape($name) + ' v') -and $_.Contains(" $source]") })
    } else {
        $name, $version = $Spec -split '==', 2
        $hits = @($Listed | Where-Object { $_ -match ('^' + [regex]::Escape($name) + ' v' + [regex]::Escape($version) + '(\s|$)') })
    }
    $hits.Count -gt 0
}
