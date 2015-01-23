{Rpc} = require "../lib/rpc_json"
{Aes} = require '../../src/ecc/aes'
{Wallet} = require '../../src/wallet/wallet'
{WalletDb} = require '../../src/wallet/wallet_db'
{WalletAPI} = require '../../src/client/wallet_api'
{PublicKey} = require '../../src/ecc/key_public'

secureRandom = require 'secure-random'

PASSWORD = "Password00"
PAY_FROM = "delegate0" #(if p=process.env.PAY_FROM then p else "delegate0")

new_wallet_api= (rpc, backup_file = '../fixtures/wallet.json') ->
    wallet_api = if backup_file
        wallet_json_string = JSON.stringify require backup_file
        # JSON.parse is used to clone (so internals can't change)
        wallet_object = JSON.parse wallet_json_string
        new WalletAPI(rpc)._open_from_wallet_db new WalletDb wallet_object
    else
        throw new Error 'not used...'
        # create an empty wallet
        entropy = secureRandom.randomUint8Array 1000
        Wallet.add_entropy new Buffer entropy
        wallet_db = Wallet.create 'TestWallet', PASSWORD, brain_key=false, save=false
        new WalletAPI(rpc)._open_from_wallet_db wallet_db
    (# avoid a blockchain deterministic key conflit
        rnd = 0
        rnd += i for i in secureRandom.randomUint8Array 10
        wallet_api.wallet.wallet_db.set_child_key_index rnd, save = false
    )
    wallet_api.unlock 10, PASSWORD
    wallet_api

### 
TODO: mail

All accounts default to init0 as there mail server
wallet_account_create init0
wallet_account_register init0 delegate0 {"mail_server_endpoint":"127.0.0.1:45000"}
###

describe "Account", ->
    
    beforeEach ->
        @rpc=new Rpc(debug=on, 45000, "localhost", "test", "test")
    
    afterEach ->
        @rpc.close()
    
    it "wallet_transfer", (done) ->
        wallet_api = new_wallet_api @rpc
        wallet_api.transfer(100.500019, 'XTS', 'delegate0', 'delegate1').then(
            (trx)->
               throw new Error 'missing trx' unless trx.trx
               done()
       ).done()
    
    it "list_accounts", (done) ->
        suffix = secureRandom.randomBuffer(2).toString 'hex'
        wallet_api = new_wallet_api @rpc
        wallet_api.account_create("newaccount-"+suffix).then (key)->
            accounts = wallet_api.list_accounts()
            if accounts.length is 0
                throw new Error "could not fetch any accounts"
            
            for account in accounts
                if account.name is "newaccount-"+suffix
                    done()
                    return
            
            throw new Error "list_accounts did not return a new account"
        .done()
    
    it "account_create", (done) ->
        suffix = secureRandom.randomBuffer(2).toString 'hex'
        wallet_api = new_wallet_api @rpc
        wallet_api.account_create("newaccount-"+suffix).then (key)->
            PublicKey.fromBtsPublic key
            account = wallet_api.get_account "newaccount-"+suffix
            throw new Error "could not fetch new account" unless account
            
            wallet_api.account_create("newaccount-"+suffix).then (key)->
                throw new Error "allowed to create an account that already exists"
            ,(error)->
                done()
            
        .done()
    
    it "account_balance (none)", (done) ->
        wallet_api = new_wallet_api @rpc
        wallet_api.account_balance("account_does_not_exist").then (balances)->
            unless balances?.length is 0
                throw new Error 'expecting empty array'
            done()
        .done()
    
    it "account_balance (single)", (done) ->
        wallet_api = new_wallet_api @rpc
        wallet_api.account_balance("delegate0").then (balances)->
            console.log '... balances',JSON.stringify balances
            unless balances?[0]?[0] is "delegate0"
                throw new Error('invalid')
            done()
        .done()
    
    ## core dump?
    it "account_balance (multiple)", (done) ->
        @rpc.debug = off
        wallet_api = new_wallet_api @rpc
        @timeout 10*1000
        wallet_api.account_balance().then (balances)->
            #console.log '... balances',JSON.stringify balances,null,1
            unless balances[0]?.length > 1
                throw new Error('invalid')
            
            done()
        .finally ()=>@rpc.debug = on
        .done()
    ##
    
    it "account_transaction_history", (done) ->
        wallet_api = new_wallet_api @rpc
        wallet_api.chain_database.sync_transactions().then ()->
            history = wallet_api.account_transaction_history()
            throw new Error 'no history' unless history?.length > 0
            done()
        .done()
    
    #it "wallet_transfer_to_address (public)", (done) ->
    #    wallet_api = new_wallet_api @rpc
    #    address = "XTS2Kpf4whNd3TkSi6BZ6it4RXRuacUY1qsj" # delegate1
    #    wallet_api.transfer_to_address(
    #        amount = 10000
    #        asset = "XTS"
    #        from = PAY_FROM
    #        to_address = address
    #        memo_message = "test"
    #        vote_method = ""#vote_recommended"
    #    ).then (trx) ->
    #        EC.throw 'expecting transaction' unless trx
    #        #console.log trx
    #        done()
    #    .done()
    
    #wallet_transfer=(wallet_api, data)->
    #    console.log "\twallet_transfer "+(JSON.stringify data)
    #    wallet_api.transfer(
    #        data.amount
    #        data.asset
    #        data.from
    #        data.to
    #        data.memo
    #        data.vote
    #    ).then (trx) ->
    #        EC.throw 'expecting transaction' unless trx
    #        #console.log trx
    #    .done()
   
    it "account_register", (done) ->
        wallet_api = new_wallet_api @rpc, '../fixtures/del.json'
        suffix = secureRandom.randomBuffer(2).toString 'hex'
        try
            wallet_api.account_create("bob-" + suffix).then (key)->
                wallet_api.account_register(
                    account_name = "bob-" + suffix
                    pay_from_account = PAY_FROM
                    public_data = null#{data:'value'}
                    delegate_pay_rate = -1
                    account_type = "titan_account"
                ).then (trx)=>
                    EC.throw 'expecting transaction' unless trx
                    #console.log trx
                    done()
                .done()
        catch ex
            console.log 'ex',ex
    
    it "dump_private_key", ->
        wallet_api = new_wallet_api @rpc
        private_key_hex = wallet_api.dump_private_key 'delegate0'
        EC.throw 'expecting private_key_hex' unless private_key_hex
    
    
    it "wallet_create", ->
        WalletDb.delete 'TestWallet'
        entropy = secureRandom.randomUint8Array 1000
        Wallet.add_entropy new Buffer entropy
        Wallet.create 'TestWallet', PASSWORD, brain_key=null, save=true
        WalletDb.delete 'TestWallet'
    
