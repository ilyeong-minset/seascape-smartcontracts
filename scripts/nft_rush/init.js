let NftRush = artifacts.require("NftRush");
let LpToken = artifacts.require("LP_Token");
let Crowns = artifacts.require("CrownsToken");
let Nft = artifacts.require("SeascapeNFT");
let Factory = artifacts.require("NFTFactory");

let accounts;
let interval = 10;  // seconds
let period = 180;   // 3 min
let generation = 0;

/**
 * For test purpose, starts a game session
 */
module.exports = async function(callback) {
    let res = init();
    console.log("Session started successfully");
    
    callback(null, res);
};

let init = async function() {
    web3.eth.getAccounts(function(err,res) { accounts = res; });

    let nftRush = await NftRush.deployed();
    let factory = await Factory.deployed();
    let nft     = await Nft.deployed();
    let crowns = await Crowns.deployed();
    
    //should add nft rush as generator role in nft factory
    await factory.addGenerator(nftRush.address, {from: accounts[0]});

    //should set nft factory in nft
    await nft.setFactory(factory.address);

    //should start a session
    let startTime = Math.floor(Date.now()/1000) + 1;
    return await nftRush.startSession(interval,
				      period,
				      startTime,
				      generation,
				      {from: accounts[0]});
}.bind(this);


// ------------------------------------------------------------
// Leaderboard related data
// ------------------------------------------------------------
let addDailyWinners = async function(nftRush, lastSessionId) {
    // in nftrush.sol contract, at the method claimDailyNft
    // comment requirement of isDailWinnersAddress against false checking

    let winners = [];
    for(var i=0; i<10; i++) {
	if (i%2 == 0) {
	    winners.push(accounts[0]);
	} else {
	    winners.push(accounts[1]);
	}
    }

    // contract deployer. only it can add winners list into the contract
    let owner = accounts[0];

    try {
	await nftRush.addDailyWinners(lastSessionId, winners);
    } catch(e) {
	if (e.reason == "NFT Rush: already set or too early") {
	    return true;
	}
    }
};

let claimDailyNft = async function(nftRush, lastSessionId) {
    let nftAmount = await nftRush.dailyClaimablesAmount(accounts[0]);
    nftAmount = parseInt(nftAmount.toString());

    if (!nftAmount) {
	return true;
    }

    for(var i=0; i<nftAmount; i++) {
	await nftRush.claimDailyNft();

	let updatedAmount = await nftRush.dailyClaimablesAmount(accounts[0]);
	updatedAmount = parseInt(updatedAmount.toString());

	//daily claimable amount didn't updated after nft claiming
	if (updatedAmount != nftAmount - (i+1)) {
	    return false;
	}
    }

    let zeroAmount = await nftRush.dailyClaimablesAmount(accounts[0]);
    zeroAmount = parseInt(zeroAmount.toString());

    // daily claimables after all claims should be equal to 0
    if (zeroAmount != 0) {
	return false;
    }

    await nftRush.claimDailyNft();
};
