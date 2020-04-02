#include "./utils/conversions.ligo"
#include "./utils/math.ligo"
#include "./partials/tokenActions.ligo"

type tokenInformation is record
  contractAddress: address;
  tokenDecimals: nat;
end

type balanceInfo is record
  tezAmount: tez;
  blockTimestamp: timestamp;
end

type exchangeRatioInformation is record
  ratio: nat;
  blockTimestamp: timestamp;
end

type action is
| Deposit of (unit)
| Withdraw of (nat)
| AddLiquidity of (unit)
| UpdateExchangeRatio of (nat)
| UpdateCollateralRatio of (nat)
| UpdateTokenAddress of (address)
| UpdateTokenDecimals of (nat)
| GetExchangeRatio of (unit * contract(exchangeRatioInformation))
| GetBalanceOf of (address * contract(balanceInfo))

type store is record  
  owner: address;
  deposits: big_map(address, balanceInfo);
  borrows: big_map(address, balanceInfo);
  exchangeRatio: exchangeRatioInformation; // Between TEZ and the pToken, this must be variable, but for now is ok
  collateralRatio: nat; // The collateral ratio that borrows must maintain (e.g. 2 implies 2:1), this represents the percentage of supplied value that can be actively borrowed at any given time.
  borrowInterest: nat;
  supplyInterest: nat;
  liquidity: tez;
  token: tokenInformation;
end

const emptyOps: list(operation) = list end;

type return is list(operation) * store

function getSender(const mock: bool): address is
  block {
    var senderAddress: address := sender;  
    if mock 
      then senderAddress := ("tz1MZ4GPjAA2gZxKTozJt8Cu5Gvu6WU2ikZ4" : address);
      else skip
  } with(senderAddress)

function calculateInterest(const elapsedBlocks: int; const deposit: tez; var store: store): tez is
  block {
    const anualBlocks: int = 522119;
    
    const accruedInterest: int = (elapsedBlocks * 100) / anualBlocks;
    const depositAsNat: nat = tezToNatWithMutez(deposit);
    const depositAsInt: int = natToInt(depositAsNat);
    const accruedTezAsInt: int = (accruedInterest * natToInt(store.exchangeRatio.ratio) * depositAsInt)/10000;
    const newDepositAsInt: int = depositAsInt + accruedTezAsInt;

    const interest: tez = natToMutez(abs(newDepositAsInt));

  } with(interest)

function incrementExchangeRatio(var store: store): unit is
  block {
    const elapsedBlocks: int = now - store.exchangeRatio.blockTimestamp;
    if (elapsedBlocks < 10000)
      then skip;
      else block {
        var ratioValue : nat := store.exchangeRatio.ratio + 1n;
        patch store.exchangeRatio with record [ ratio = ratioValue ]
      }
  } with (unit)

function updateExchangeRatio(const value : nat ; var store : store) : return is
 block {
  // Fail if is not the owner
  if (sender =/= store.owner) 
    then failwith("You must be the owner of the contract to update the exchange ratio");
    else block {
      patch store.exchangeRatio with record [ratio = value]
    }
 } with (emptyOps, store)

 function updateCollateralRatio(const value : nat ; var store : store) : return is
 block {
  // Fail if is not the owner
  if (sender =/= store.owner) 
    then failwith("You must be the owner of the contract to update the collateral ratio");
    else block {
      store.collateralRatio := value;
    }
 } with (emptyOps, store)

function updateTokenAddress(const contractAddress : address ; var store : store) : return is
 block {
  // Fail if is not the owner
  if (sender =/= store.owner) 
    then failwith("You must be the owner of the contract to update the token address");
    else  block {
      patch store.token with record [contractAddress = contractAddress]
    }
 } with (emptyOps, store)

function updateTokenDecimals(const tokenDecimals : nat ; var store : store) : return is
 block {
  // Fail if is not the owner
  if (sender =/= store.owner) 
    then failwith("You must be the owner of the contract to update the token decimals");
    else  block {
      patch store.token with record [tokenDecimals = tokenDecimals]   
    }
 } with (emptyOps, store)

function tokenProxy (const action : tokenAction; const store : store): operation is
  block {
    const tokenContract: contract (tokenAction) =
      case (Tezos.get_contract_opt (store.token.contractAddress) : option (contract (tokenAction))) of
        Some (contract) -> contract
      | None -> (failwith ("Contract not found.") : contract (tokenAction))
      end;
    const proxyOperation : operation = Tezos.transaction (action, 0mutez, tokenContract);
  } with proxyOperation

function getDeposit(var senderAddress: address; var store: store): balanceInfo is 
  block {
    var depositsMap: big_map(address, balanceInfo) := store.deposits;
    var deposit: option(balanceInfo) := depositsMap[senderAddress];
  } with
  case deposit of          
    | Some(depositItem) -> depositItem
    | None -> record tezAmount = 0tez; blockTimestamp = now; end
  end;

function updateDeposit(var senderAddress: address; var amountDeposit: tez; var store: store): balanceInfo is 
  block {
    var depositItem: balanceInfo := getDeposit(senderAddress, store);
   
    // calculate interest             
    const elapsedBlocks:int = now - depositItem.blockTimestamp;
    depositItem.tezAmount := depositItem.tezAmount + calculateInterest(elapsedBlocks, depositItem.tezAmount, store) + amountDeposit;
    depositItem.blockTimestamp := now;

    store.deposits[senderAddress] := depositItem;
    store.liquidity := store.liquidity + amountDeposit;
} with depositItem

function depositImp(var store: store): return is
  block {
    var operations: list(operation) := nil;

    if amount = 0mutez
      then failwith("No tez transferred!");
      else block { 
          // If ratio is zero, failwith
        if store.exchangeRatio.ratio = 0n
          then failwith("Exchange ratio must not be zero!");
          else block {    
            const senderAddress: address = getSender(False);

            // Setting the deposit to the sender
            var depositItem: balanceInfo := updateDeposit(senderAddress, amount, store);

            // Increment exchangeRatio
            incrementExchangeRatio(store);

            // TODO: try to get the decimals property from the token contract

            // mintTo tokens to the senderAddress
            const amountInNat: nat = tezToNatWithTz(amount);
            // The user receives a quantity of pTokens equal to the underlying tokens supplied, divided by the current Exchange Rate.
            const decimals: nat = store.token.tokenDecimals;
            const amountInNatExchangeRate: int = natToInt(amountInNat / store.exchangeRatio.ratio) * pow(10, natToInt(decimals));
            const amountToMint: nat = intToNat(amountInNatExchangeRate);

            const tokenProxyMintToOperation: operation = tokenProxy(MintTo(senderAddress, amountToMint), store);
            operations := list
            tokenProxyMintToOperation
            end;
          }      
      }
  } with(operations, store)

function withdrawImp(var amountToWithdraw: nat; var store: store): return is
  block {  
    var operations: list(operation) := nil;

    if amountToWithdraw = 0n
      then failwith("No amount to withdraw!"); 
      else block {   
        // If ratio is zero, failwith
        if store.exchangeRatio.ratio = 0n
          then failwith("Exchange ratio must not be zero!");
          else block {    
            const senderAddress: address = getSender(False);
            var depositItem: balanceInfo := updateDeposit(senderAddress, 0tez, store);

            // The amount redeemed must be less than the user's account liquidity 
            // and the pool's available liquidity.
            const amountToWithdraInTz: tez = natToTz(amountToWithdraw);
            if amountToWithdraInTz >= depositItem.tezAmount or amountToWithdraInTz >= store.liquidity
              then failwith("No tez available to withdraw!");
              else block {
                // Increment exchangeRate
                incrementExchangeRatio(store);

                // Calculate amount to burn
                const amountInTokensToBurn: nat = amountToWithdraw / store.exchangeRatio.ratio;

                // Burn pTokens
                const tokenProxyBurnToOperation: operation = tokenProxy(BurnTo(senderAddress, amountInTokensToBurn), store);

                // Update user's balance
                depositItem.tezAmount := depositItem.tezAmount - amountToWithdraInTz;
                depositItem.blockTimestamp := now;
                store.deposits[senderAddress] := depositItem;            

                // Update liquidity
                store.liquidity := store.liquidity - amountToWithdraInTz;

                // Create the operation to transfer tez to sender
                const receiver: contract(unit) = get_contract(senderAddress);
                const payoutOperation: operation = Tezos.transaction(unit, amountToWithdraInTz, receiver);
                operations:= list 
                  payoutOperation
                end;
              }
          }
      }
  } with(operations, store)

function addLiquidity( var store : store) : return is
 block {
  // Fail if is not the owner
  if (sender =/= store.owner) 
    then failwith("You must be the owner of the contract to add liquidity");
    else block {
      if (amount = 0mutez)
        then failwith("No tez transferred!");
        else block {
          store.liquidity := store.liquidity + amount;
        }
    }
} with (emptyOps, store)

function getExchangeRatio (const callback : contract(exchangeRatioInformation); var store : store) : return is
  block {
    var exchangeRatio: exchangeRatioInformation := store.exchangeRatio;

    const exchangeRatioOperation: operation = Tezos.transaction(exchangeRatio, 0mutez, callback);
    operations := list 
        exchangeRatioOperation 
    end;  
} with (operations, store);


function getBalanceOf (const accountAddress: address; const callback : contract(balanceInfo); var store : store) : return is
  block {
      var operations: list(operation) := nil;

      var depositsMap: big_map(address, balanceInfo) := store.deposits;    
      var senderbalanceInfo: option(balanceInfo) := depositsMap[accountAddress];            

      case senderbalanceInfo of          
        | None -> failwith("Account address not found")
        | Some(di) -> 
          block {
            const balanceOperation: operation = Tezos.transaction(di, 0mutez, callback);
            operations := list 
                balanceOperation 
            end;   
          }
      end; 
} with (operations, store);

function main (const action: action; var store: store): return is
  block {
    skip
  } with case action of
    | Deposit(n) -> depositImp(store)
    | Withdraw(n) -> withdrawImp(n, store)
    | UpdateExchangeRatio(n) -> updateExchangeRatio(n, store)
    | UpdateCollateralRatio(n) -> updateCollateralRatio(n, store)
    | AddLiquidity(n) ->  addLiquidity(store)
    | UpdateTokenAddress(n) -> updateTokenAddress(n, store)
    | UpdateTokenDecimals(n) -> updateTokenDecimals(n, store)
    | GetExchangeRatio(n) -> getExchangeRatio(n.1, store)
    | GetBalanceOf(n) -> getBalanceOf(n.0, n.1, store)
  end;  