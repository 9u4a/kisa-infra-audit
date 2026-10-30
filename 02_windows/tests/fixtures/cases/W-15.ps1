# W-15 케이스. 가이드: 양호 = 개인 키를 사용할 때마다 암호 입력(ForceKeyProtection=2) / 취약 = 매번 입력받지 않음(미설정, 1=처음 사용할 때만)
@{
    States = [ordered]@{
        'unset'       = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Cryptography\Protect'; N = 'ForceKeyProtection'; V = $null }) }
        'prompt-once' = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Cryptography\Protect'; N = 'ForceKeyProtection'; V = 1 }) }
        'always'      = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Cryptography\Protect'; N = 'ForceKeyProtection'; V = 2 }) }
    }
    Fix    = @{ From = 'unset' }
}
