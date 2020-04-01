function natToTz(const val: nat): tez is val * 1tz

function natToMutez(const val: nat): tez is val * 1mutez

function tezToNatWithMutez(const val: tez): nat is val / 1mutez

function tezToNatWithTz(const val: tez): nat is val / 1tz

function natToInt(const val: nat): int is val + 0

function intToNat(const val: int): nat is block { 
  var res: nat := 0n;
  if(val >= 0)
    then res := abs(val)
    else failwith("Not posible to convert from negative values")
} with res