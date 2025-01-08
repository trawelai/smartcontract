// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.9;

// Importing necessary contracts and interfaces

import "./ERC20.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./Ownable.sol";

contract TrawelAI is ERC20, Ownable 
{
    using SafeMath for uint256;

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;
    address public constant deadAddress = address(0xdead);

    bool private swapping;

    address public marketingWallet;
    address public devWallet;
    address public buyBackWallet;
    address public leftOverLiqAddress;

    
    uint256 public maxTransactionAmount;
    uint256 public maxWallet;
    uint8 private _decimals;

    bool public limitsInEffect = true;
    bool public tradingActive  = false;
    bool public swapEnabled    = false;
    bool public rescueSwap     = false;
    
    uint256 public tradingActiveBlock;
        
    uint256 public buyTotalFees;
    uint256 public buyMarketingFee;
    uint256 public buyLiquidityFee;
    uint256 public buyDevFee;
    uint256 public buyBuyBackFee;
    
    uint256 public sellTotalFees;
    uint256 public sellMarketingFee;
    uint256 public sellLiquidityFee;
    uint256 public sellDevFee;
    uint256 public sellBuyBackFee;
    
    uint256 public tokensForMarketing;
    uint256 public tokensForLiquidity;
    uint256 public tokensForDev;
    uint256 public tokensForBuyBack;
    
    /******************/

    // exlcude from fees and max transaction amount
    mapping (address => bool) private _isExcludedFromFees;
    mapping (address => bool) public _isExcludedMaxTransactionAmount;

    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping (address => bool) public automatedMarketMakerPairs;

    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);

    event ExcludeFromFees(address indexed account, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event marketingWalletUpdated(address indexed newWallet, address indexed oldWallet);
    
    event devWalletUpdated(address indexed newWallet, address indexed oldWallet);
    
    event buyBackWalletUpdated(address indexed newWallet, address indexed oldWallet);
	
    event leftOverLiqWalletUpdated(address indexed newWallet, address indexed oldWallet);		

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiquidity
    );

    event BuyBackTriggered(uint256 amount);
    
    event OwnerForcedSwapBack(uint256 timestamp);

    constructor(address payable _marketingWallet,address payable _buyBackWallet,address payable _devProjectWallet) ERC20("Trawel.AI", "TrawelAI") {

        address _owner = msg.sender;

        _decimals = 9;

        uint256 totalSupply = 1000000000000 * (10**_decimals);
        
        maxTransactionAmount = totalSupply * 1 / 100; // 1% maxTransactionAmountTxn
        maxWallet            = totalSupply * 1 / 100; // 1% maxWallet

        buyMarketingFee     = 3;
        buyLiquidityFee     = 2;
        buyDevFee           = 3;
        buyBuyBackFee       = 2;
        buyTotalFees        = buyMarketingFee + buyLiquidityFee + buyDevFee + buyBuyBackFee;
        
        sellMarketingFee    = 3;
        sellLiquidityFee    = 2;
        sellDevFee          = 3;
        sellBuyBackFee      = 2;
        sellTotalFees       = sellMarketingFee + sellLiquidityFee + sellDevFee + sellBuyBackFee;

        marketingWallet     = _marketingWallet;
		devWallet 			= _devProjectWallet;
    	buyBackWallet       = _buyBackWallet;
		leftOverLiqAddress	= _marketingWallet;
        


        address currentRouter;
        
        //Adding Variables for all the routers for easier deployment for our customers.
        if (block.chainid == 56) {
            currentRouter = 0x10ED43C718714eb63d5aA57B78B54704E256024E; // PCS Router
        } else if (block.chainid == 97) {
            currentRouter = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1; // PCS Testnet
        } else if (block.chainid == 43114) {
            currentRouter = 0x60aE616a2155Ee3d9A68541Ba4544862310933d4; //Avax Mainnet
        } else if (block.chainid == 137) {
            currentRouter = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff; //Polygon Ropsten
        } else if (block.chainid == 250) {
            currentRouter = 0xF491e7B69E4244ad4002BC14e878a34207E38c29; //SpookySwap FTM
        } else if (block.chainid == 3) {
            currentRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; //Ropsten
        } else if (block.chainid == 1 || block.chainid == 4) {
            currentRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; //Mainnet
        } else {
            revert();
        }

        //End of Router Variables.

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(currentRouter);

        excludeFromMaxTransaction(address(_uniswapV2Router), true);
        uniswapV2Router = _uniswapV2Router;
        
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());
        excludeFromMaxTransaction(address(uniswapV2Pair), true);
        _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);

        // exclude from paying fees or having max transaction amount
        excludeFromFees(_owner, true);
        excludeFromFees(address(this), true);
        excludeFromFees(address(0xdead), true);
	        
		
        excludeFromMaxTransaction(_owner, true);
        excludeFromMaxTransaction(address(this), true);
        excludeFromMaxTransaction(address(0xdead), true);
		excludeFromMaxTransaction(address(buyBackWallet), true);
        
        /*		
			"_mint" is an internal function in ERC20.sol that is only called here, 
			and CANNOT be called ever again as the constructor can be called once 
			in a lifetime during the contract deployment only
        */
        _mint(_owner, totalSupply);
        transferOwnership(_owner);
    }

    //to recieve ETH from uniswapV2Router when swaping
    receive() external payable {

  	}

    // once enabled, can never be turned off
    function enableTrading() external onlyOwner {
        tradingActive = true;
        swapEnabled = true;
        tradingActiveBlock = block.number;
    }
    
    // remove limits after token is stable
    function removeLimits() external onlyOwner returns (bool){
        limitsInEffect = false;
        return true;
    }
    
    function airdropToWallets(address[] memory airdropWallets, uint256[] memory amounts) external onlyOwner returns (bool){
        require(!tradingActive, "Trading is already active, cannot airdrop after launch.");
        require(airdropWallets.length == amounts.length, "arrays must be the same length");
        require(airdropWallets.length < 200, "Can only airdrop 200 wallets per txn due to gas limits"); // allows for airdrop + launch at the same exact time, reducing delays and reducing sniper input.
        for(uint256 i = 0; i < airdropWallets.length; i++){
            address wallet = airdropWallets[i];
            uint256 amount = amounts[i];
            _transfer(msg.sender, wallet, amount);
        }
        return true;
    }
    
    function updateMaxAmount(uint256 newNum) external onlyOwner {
        require(newNum >= (totalSupply() * 1 / 100)/(10**_decimals), "Cannot set maxTransactionAmount lower than 1%");
        maxTransactionAmount = newNum * (10**_decimals);
    }
    
    function updateMaxWallet(uint256 newNum) external onlyOwner {
        require(newNum >= (totalSupply() * 1 / 100)/(10**_decimals), "Cannot set maxTransactionAmount lower than 1%");
        maxWallet= newNum * (10**_decimals);
    }
	
	function setLeftOverLiqWalletAddress(address newAddress) external onlyOwner() {
		emit leftOverLiqWalletUpdated(newAddress, leftOverLiqAddress);
        leftOverLiqAddress = newAddress;
    }		
    
    function excludeFromMaxTransaction(address updAds, bool isEx) public onlyOwner {
        _isExcludedMaxTransactionAmount[updAds] = isEx;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
    
    // only use to disable contract sales if absolutely necessary (emergency use only)
    function updateSwapEnabled(bool enabled) external onlyOwner(){
        swapEnabled = enabled;
    }

    // only use this to disable swapback and send tax in form of tokens
    function updateRescueSwap(bool enabled) external onlyOwner(){
        rescueSwap = enabled;
    }
    
	/*	
		The maximum tax applicable to the transaction cannot exceed 10%. 
		This limitation ensures that even the contract owner is unable to increase 
		the tax beyond this threshold. Therefore, investors can place their 
		trust in the contract and enjoy peaceful and restful nights.
	*/	
    function updateBuyFees(uint256 _marketingFee, uint256 _liquidityFee, uint256 _devFee, uint256 _buyBackFee) external onlyOwner {
        buyMarketingFee = _marketingFee;
        buyLiquidityFee = _liquidityFee;
        buyDevFee = _devFee;
        buyBuyBackFee = _buyBackFee;
        buyTotalFees = buyMarketingFee + buyLiquidityFee + buyDevFee + buyBuyBackFee;
        require(buyTotalFees <= 10, "The taxes must keep fees at 10% or less");
    }

	/*	
		The maximum tax applicable to the transaction cannot exceed 10%. 
		This limitation ensures that even the contract owner is unable to increase 
		the tax beyond this threshold. Therefore, investors can place their 
		trust in the contract and enjoy peaceful and restful nights.
	*/	
    function updateSellFees(uint256 _marketingFee, uint256 _liquidityFee, uint256 _devFee, uint256 _buyBackFee) external onlyOwner {
        sellMarketingFee = _marketingFee;
        sellLiquidityFee = _liquidityFee;
        sellDevFee = _devFee;
        sellBuyBackFee = _buyBackFee;
        sellTotalFees = sellMarketingFee + sellLiquidityFee + sellDevFee + sellBuyBackFee;
        require(sellTotalFees <= 10, "The taxes must keep fees at 10% or less");
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        require(pair != uniswapV2Pair, "The pair cannot be removed from automatedMarketMakerPairs");

        _setAutomatedMarketMakerPair(pair, value);
    }
    
    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        automatedMarketMakerPairs[pair] = value;

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function updateMarketingWallet(address newMarketingWallet) external onlyOwner {
        emit marketingWalletUpdated(newMarketingWallet, marketingWallet);
        marketingWallet = newMarketingWallet;
    }
    
    function updateDevWallet(address newWallet) external onlyOwner {
        emit devWalletUpdated(newWallet, devWallet);
        devWallet = newWallet;
    }
    
    function updateBuyBackWallet(address newWallet) external onlyOwner {
        emit buyBackWalletUpdated(newWallet, buyBackWallet);
        buyBackWallet = newWallet;
    }
    

    function isExcludedFromFees(address account) external view returns(bool) {
        return _isExcludedFromFees[account];
    }
    
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        if(!tradingActive){
            require(_isExcludedFromFees[from] || _isExcludedFromFees[to], "Trading is not active.");
        }
         if(amount == 0) {
            super._transfer(from, to, 0);
            return;
        }
        
        if(limitsInEffect){
            if (
                from != owner() &&
                to != owner() &&
                to != address(0) &&
                to != address(0xdead) &&
                !(_isExcludedFromFees[from] || _isExcludedFromFees[to]) &&
                !swapping
            ){
                 
                //when buy
                if (automatedMarketMakerPairs[from] && !_isExcludedMaxTransactionAmount[to]) {
                        require(amount <= maxTransactionAmount, "Buy transfer amount exceeds the maxTransactionAmount.");
                        require(amount + balanceOf(to) <= maxWallet, "Max wallet exceeded");
                }
                
                //when sell
                else if (automatedMarketMakerPairs[to] && !_isExcludedMaxTransactionAmount[from]) {
                        require(amount <= maxTransactionAmount, "Sell transfer amount exceeds the maxTransactionAmount.");
                }
                else {
                    require(amount + balanceOf(to) <= maxWallet, "Max wallet exceeded");
                }
            }
        }
        
		uint256 contractTokenBalance = balanceOf(address(this));
        
        bool canSwap = contractTokenBalance > 0;

        if( 
            canSwap &&
            swapEnabled &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            !_isExcludedFromFees[from] &&
            !_isExcludedFromFees[to]
        ) {
            swapping = true;
            
            swapBack();

            swapping = false;
        }
        
        bool takeFee = !swapping;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if(_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }
        
        uint256 fees = 0;
        // only take fees on buys/sells, do not take on wallet transfers
        if(takeFee){
            
            if(tradingActiveBlock == block.number && (automatedMarketMakerPairs[to] || automatedMarketMakerPairs[from])){
                fees = amount.mul(99).div(100);
                tokensForLiquidity += fees * 33 / 99;
                tokensForBuyBack += fees * 33 / 99;
                tokensForMarketing += fees * 33 / 99;
            }
            // on sell
            else if (automatedMarketMakerPairs[to]){
                if (sellTotalFees > 0){
                    fees = amount.mul(sellTotalFees).div(100);
                    tokensForLiquidity += fees * sellLiquidityFee / sellTotalFees;
                    tokensForDev += fees * sellDevFee / sellTotalFees;
                    tokensForMarketing += fees * sellMarketingFee / sellTotalFees;
                    tokensForBuyBack += fees * sellBuyBackFee / sellTotalFees;
                }
            }
            // on buy
            else if(automatedMarketMakerPairs[from]) {
                if (buyTotalFees > 0){
                    fees = amount.mul(buyTotalFees).div(100);
                    tokensForLiquidity += fees * buyLiquidityFee / buyTotalFees;
                    tokensForDev += fees * buyDevFee / buyTotalFees;
                    tokensForMarketing += fees * buyMarketingFee / buyTotalFees;
                    tokensForBuyBack += fees * buyBuyBackFee / buyTotalFees;
                }
            }
            
            if(fees > 0){    
                super._transfer(from, address(this), fees);
            }
        	
        	amount -= fees;
        }

        super._transfer(from, to, amount);
    }

    function swapTokensForEth(uint256 tokenAmount) private {

        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
        
    }
    
    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        try uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            leftOverLiqAddress,
            block.timestamp
        ) {} catch {}
    }

    function resetTaxAmount() public onlyOwner {
        tokensForLiquidity = 0;
        tokensForMarketing = 0;
        tokensForDev = 0;
        tokensForBuyBack = 0;
    }

    function swapBack() private {
        uint256 contractBalance = balanceOf(address(this));

        if (rescueSwap){
            if (contractBalance > 0){
                super._transfer(address(this), marketingWallet, contractBalance);
            }
            return;
        }

        uint256 totalTokensToSwap = tokensForLiquidity + tokensForMarketing + tokensForDev + tokensForBuyBack;
        bool success;
        
        if(contractBalance == 0 || totalTokensToSwap == 0) {return;}
        
        // Halve the amount of liquidity tokens
        uint256 liquidityTokens = contractBalance * tokensForLiquidity / totalTokensToSwap / 2;
        uint256 amountToSwapForETH = contractBalance.sub(liquidityTokens);
        
        uint256 initialETHBalance = address(this).balance;

        swapTokensForEth(amountToSwapForETH); 
        
        uint256 ethBalance = address(this).balance.sub(initialETHBalance);
        
        uint256 ethForMarketing = ethBalance.mul(tokensForMarketing).div(totalTokensToSwap);
        uint256 ethForDev = ethBalance.mul(tokensForDev).div(totalTokensToSwap);
        uint256 ethForBuyBack = ethBalance.mul(tokensForBuyBack).div(totalTokensToSwap);
        
        uint256 ethForLiquidity = ethBalance - ethForMarketing - ethForDev - ethForBuyBack;
        
        tokensForLiquidity = 0;
        tokensForMarketing = 0;
        tokensForDev = 0;
        tokensForBuyBack = 0;
        
        (success,) = address(devWallet).call{value: ethForDev}("");
        (success,) = address(buyBackWallet).call{value: ethForBuyBack}("");
        
        if(liquidityTokens > 0 && ethForLiquidity > 0){
            addLiquidity(liquidityTokens, ethForLiquidity);
            emit SwapAndLiquify(amountToSwapForETH, ethForLiquidity, tokensForLiquidity);
        }
        
        (success,) = address(marketingWallet).call{value: address(this).balance}("");
        
    }
}