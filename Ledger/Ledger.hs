{-|

A 'Ledger' stores, for efficiency, a 'RawLedger' plus its tree of account
names, a map from account names to 'Account's, and the display precision.
Typically it has also has had the uninteresting 'Entry's filtered out.

-}

module Ledger.Ledger
where
import qualified Data.Map as Map
import Data.Map ((!))
import Ledger.Utils
import Ledger.Types
import Ledger.Amount
import Ledger.AccountName
import Ledger.Transaction
import Ledger.RawLedger
import Ledger.Entry


instance Show Ledger where
    show l = printf "Ledger with %d entries, %d accounts\n%s"
             ((length $ entries $ rawledger l) +
              (length $ modifier_entries $ rawledger l) +
              (length $ periodic_entries $ rawledger l))
             (length $ accountnames l)
             (showtree $ accountnametree l)

-- | Convert a raw ledger to a more efficient cached type, described above.  
cacheLedger :: RawLedger -> Ledger
cacheLedger l = 
    let 
        ant = rawLedgerAccountNameTree l
        anames = flatten ant
        ts = rawLedgerTransactions l
        sortedts = sortBy (comparing account) ts
        groupedts = groupBy (\t1 t2 -> account t1 == account t2) sortedts
        txnmap = Map.union 
               (Map.fromList [(account $ head g, g) | g <- groupedts])
               (Map.fromList [(a,[]) | a <- anames])
        txnsof = (txnmap !)
        subacctsof a = filter (isAccountNamePrefixOf a) anames
        subtxnsof a = concat [txnsof a | a <- [a] ++ subacctsof a]
        balmap = Map.union 
               (Map.fromList [(a, (sumTransactions $ subtxnsof a)) | a <- anames])
               (Map.fromList [(a,nullamt) | a <- anames])
        amap = Map.fromList [(a, Account a (txnmap ! a) (balmap ! a)) | a <- anames]
    in
      Ledger l ant amap

-- | List a 'Ledger' 's account names.
accountnames :: Ledger -> [AccountName]
accountnames l = drop 1 $ flatten $ accountnametree l

-- | Get the named account from a ledger.
ledgerAccount :: Ledger -> AccountName -> Account
ledgerAccount l a = (accountmap l) ! a

-- | List a ledger's accounts, in tree order
accounts :: Ledger -> [Account]
accounts l = drop 1 $ flatten $ ledgerAccountTree 9999 l

-- | List a ledger's top-level accounts, in tree order
topAccounts :: Ledger -> [Account]
topAccounts l = map root $ branches $ ledgerAccountTree 9999 l

-- | Accounts in ledger whose name matches the pattern, in tree order.
-- We apply ledger's special rules for balance report account matching
-- (see 'matchLedgerPatterns').
accountsMatching :: [String] -> Ledger -> [Account]
accountsMatching pats l = filter (matchLedgerPatterns True pats . aname) $ accounts l

-- | List a ledger account's immediate subaccounts
subAccounts :: Ledger -> Account -> [Account]
subAccounts l a = map (ledgerAccount l) subacctnames
    where
      allnames = accountnames l
      name = aname a
      subacctnames = filter (name `isAccountNamePrefixOf`) allnames

-- | List a ledger's transactions.
--
-- NB this sets the amount precisions to that of the highest-precision
-- amount, to help with report output. It should perhaps be done in the
-- display functions, but those are far removed from the ledger. Keep in
-- mind if doing more arithmetic with these.
ledgerTransactions :: Ledger -> [Transaction]
ledgerTransactions l = rawLedgerTransactions $ rawledger l

-- | Get a ledger's tree of accounts to the specified depth.
ledgerAccountTree :: Int -> Ledger -> Tree Account
ledgerAccountTree depth l = 
    addDataToAccountNameTree l depthpruned
    where
      nametree = accountnametree l
      depthpruned = treeprune depth nametree

-- that's weird.. why can't this be in Account.hs ?
instance Eq Account where
    (==) (Account n1 t1 b1) (Account n2 t2 b2) = n1 == n2 && t1 == t2 && b1 == b2

-- | Get a ledger's tree of accounts rooted at the specified account.
ledgerAccountTreeAt :: Ledger -> Account -> Maybe (Tree Account)
ledgerAccountTreeAt l acct = subtreeat acct $ ledgerAccountTree 9999 l

-- | Convert a tree of account names into a tree of accounts, using their
-- parent ledger.
addDataToAccountNameTree :: Ledger -> Tree AccountName -> Tree Account
addDataToAccountNameTree = treemap . ledgerAccount

