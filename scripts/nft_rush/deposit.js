let NftRush = artifacts.require("NftRush");
let LpToken = artifacts.require("LP_Token");
let Crowns = artifacts.require("CrownsToken");
let Nft = artifacts.require("SeascapeNFT");
let Factory = artifacts.require("NFTFactory");

let depositInt = "5";
let depositAmount = web3.utils.toWei(depositInt, "ether");
let accounts;

/**
 * For test purpose, starts a game session
 */
module.exports = async function(callback) {
    let res = init();
    console.log("Deposit of "+depositInt+" CWS was successful!");

    callback(null, res);
};

let init = async function() {
    web3.eth.getAccounts(function(err,res) { accounts = res; });
    let nftRush = await NftRush.deployed();
    let crowns = await Crowns.deployed();
    let lastSessionId = await nftRush.lastSessionId();
    
    return await deposit(nftRush, crowns, lastSessionId);
}.bind(this);


let deposit = async function(nftRush, crowns, lastSessionId) {
    /////// depositing token
    //should approve nft rush to spend cws of player
    await crowns.approve(nftRush.address, depositAmount, {from: accounts[0]});

    //should spend deposit in nft rush
    await nftRush.deposit(lastSessionId, depositAmount, {from: accounts[0]});    
}.bind(this);
