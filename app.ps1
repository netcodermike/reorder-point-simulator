param([Parameter(Mandatory=$true, Position=0)][string] $InputPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Read-Integer($Value, [string] $Label, [int] $Minimum, [int] $Maximum) {
    if (($Value -isnot [long] -and $Value -isnot [int]) -or $Value -lt $Minimum -or $Value -gt $Maximum) {
        throw "$Label must be a whole number from $Minimum to $Maximum"
    }
    return [int] $Value
}

function Invoke-Analysis($Payload) {
    $onHand = [long] (Read-Integer $Payload.initial 'initial' 0 1000000)
    $threshold = Read-Integer $Payload.threshold 'threshold' 0 1000000
    $quantity = Read-Integer $Payload.orderQuantity 'orderQuantity' 1 1000000
    $lead = Read-Integer $Payload.leadDays 'leadDays' 1 10000
    if ($Payload.demand -isnot [array] -or $Payload.demand.Count -lt 1 -or $Payload.demand.Count -gt 3660) {
        throw "Provide demand for 1 to 3660 days"
    }
    $openOrders = [System.Collections.Generic.Queue[object]]::new()
    $timeline = [System.Collections.Generic.List[object]]::new()
    $placed = 0
    $onOrder = 0L
    $lostSales = 0L
    for ($day = 1; $day -le $Payload.demand.Count; $day++) {
        $requested = Read-Integer $Payload.demand[$day - 1] "Day $day demand" 0 1000000
        $arrived = 0
        if ($openOrders.Count -and $openOrders.Peek().due -eq $day) {
            $arrived = $openOrders.Dequeue().quantity
            $onHand += $arrived
            $onOrder -= $arrived
        }
        $served = [Math]::Min($onHand, $requested)
        $onHand -= $served
        $lostSales += $requested - $served
        $order = $null
        if ($onHand + $onOrder -le $threshold) {
            $order = @{ due = $day + $lead; quantity = $quantity }
            $openOrders.Enqueue($order)
            $onOrder += $quantity
            $placed++
        }
        $timeline.Add(@{ day = $day; arrived = $arrived; served = $served; onHand = $onHand; order = $order })
    }
    return @{ orderCount = $placed; lostSales = $lostSales; onHand = $onHand; onOrder = $onOrder; timeline = $timeline.ToArray() }
}

try {
    $payload = Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json -AsHashtable
    if ($payload -isnot [System.Collections.IDictionary]) { throw 'Input must be a JSON object' }
    Invoke-Analysis $payload | ConvertTo-Json -Depth 30 -Compress
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 2
}
