var LPToken = artifacts.require("./LP_Token.sol");

module.exports = function(deployer, network) {
    if (network == "development") {
	deployer.deploy(LPToken).then(function(){
	    console.log("LP Test token contract was deployed at address: "+LPToken.address);
	});
    }
};

