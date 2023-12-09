// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract Auction{
    address[] internal bidders;
    mapping(address => uint256) internal amounts;
    mapping(address => uint256) internal prices;
    
    function bid(address _bidder, uint256 _amount, uint256 _price) external{
        if(amounts[_bidder] == 0)
            bidders.push(_bidder);
        
        amounts[_bidder] += _amount;
        prices[_bidder] = _price;
    }
    
    function GetBidders() external view returns(address[] memory){
        return bidders;
    }
    
    function GetAmount(address bidder) external view returns(uint256){
        return amounts[bidder];
    }
}

contract IDOLaunchPad{
    struct Config {
        address TokenAddr;
        uint256 TotalSupply;
        uint256 InitPrice;
        uint256 Duration;
        uint256 ChgInterval;
        uint256 ChgPercent;
        uint256 ChgPrice;
        uint256 ResPrice;
    }
    
    struct AuctionValues {
        bool Ended;
        bool Completed;
        uint256 TotalAmount;
        uint256 CurrentSupply;
        uint256 StartTime;
        uint256 AvgPr;
        uint256 MaxBid;
        uint256 MaxPr;
        uint256 EndPrice;
        uint256 EndPercent;
    }
    
    address internal _owner = msg.sender;
    Config internal config;
    AuctionValues internal values;
    Auction internal auction;
    mapping(address => uint256) internal tokens;
    
    constructor(address tokenAddr, uint256 _supply, uint256 _initPr, uint256 _dur, uint256 _int, uint256 _perc) {
        config = Config({
            TokenAddr : tokenAddr,
            TotalSupply : _supply,
            InitPrice : _initPr,
            Duration : _dur,
            ChgInterval : _int,
            ChgPercent : _perc,
            ChgPrice : (_initPr * _perc) / 100,
            ResPrice : _initPr - ((_dur * ((_initPr * _perc) / 100)) / _int)
        });
    }
    
    function SetConfig(address tokenAddr, uint256 _supply, uint256 _initPr, uint256 _dur, uint256 _int, uint256 _perc) external {
        require(_owner == msg.sender, "Only owner can set configuration");
        
        config = Config({
            TokenAddr : tokenAddr,
            TotalSupply : _supply,
            InitPrice : _initPr,
            Duration : _dur,
            ChgInterval : _int,
            ChgPercent : _perc,
            ChgPrice : (_initPr * _perc) / 100,
            ResPrice : _initPr - ((_dur * ((_initPr * _perc) / 100)) / _int)
        });
    }
    
    function GetConfig() external view returns(Config memory) {
        require(_owner == msg.sender, "Only owner can get configuration");
        return config;
    }
    
    function Create() external {
        require(_owner == msg.sender, "Only owner can create new auction");
        
        values = AuctionValues({
            Ended : false,
            Completed : false,
            TotalAmount : 0,
            CurrentSupply : 0,
            StartTime : block.timestamp,
            AvgPr : 0,
            MaxBid : 0,
            MaxPr : 0,
            EndPrice : 0,
            EndPercent : 0
        });
        
        auction = new Auction();
    }
    
    function Bid() external payable {
        require(values.Ended == false, "Auction round has been ended");
        
        uint256 price = GetCurrentPrice();
        if (price <= config.ResPrice)
        {
            values.EndPrice = price;
            values.EndPercent = GetDiscPer();
            values.Ended = true;
            payable(msg.sender).transfer(msg.value);
            return;
        }
        
        if (msg.value > values.MaxBid)
        {
            values.MaxBid = msg.value;
            values.MaxPr = price;
        }
        
        values.AvgPr += price;
        values.TotalAmount += msg.value;
        auction.bid(msg.sender, msg.value, price);
        CalculateSupply(price);
    }
    
    function GetDiscPer() internal view returns(uint256){
        if (values.Ended)
            return values.EndPercent;
            
        uint256 discPer = 0;
        if (block.timestamp - values.StartTime >= config.ChgInterval)
            discPer = (block.timestamp - values.StartTime) / config.ChgInterval;
        
        return 10 + (config.ChgPercent * discPer);
    }
    
    function GetCurrentPrice() internal view returns (uint256){
        if (values.Ended)
            return values.EndPrice;
            
        uint256 dropLevel = 0;
        if (block.timestamp - values.StartTime >= config.ChgInterval)
            dropLevel = (block.timestamp - values.StartTime) / config.ChgInterval;
        
        return config.InitPrice - (config.ChgPrice * dropLevel);
    }
    
    function CalculateSupply(uint256 _price) internal{
        values.CurrentSupply = values.TotalAmount / _price;
        if ((values.TotalAmount % _price) > 0)
            values.CurrentSupply += 1;
        
        if (values.CurrentSupply >= config.TotalSupply){
            values.EndPrice = _price;
            values.EndPercent = GetDiscPer();
            values.Ended = true;
        }
    }
    
    function Complete() external {
        require(_owner == msg.sender, "Only owner can complete the auction round");
        require(values.Completed == false, "Auction round has been completed already");
        
        if (values.Ended == false)
            values.Ended = true;
        
        address[] memory bidders = auction.GetBidders();
        if (bidders.length == 0){
            values.Completed = true;
            return;
        }
        
        uint256 price = values.AvgPr / bidders.length;
        if (values.MaxPr < price)
            price = values.MaxPr;
        
        uint256 amount;
        for (uint256 i = 0; i < bidders.length; i += 1){
            amount = auction.GetAmount(bidders[i]);
            tokens[bidders[i]] += amount / price;
            
            if ((tokens[bidders[i]] * price) < amount)
                tokens[bidders[i]] += 1;
        }
        
        values.Completed = true;
    }
    
    function GetStatus() external view returns(uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, bool, bool){
        return (values.StartTime, config.Duration, config.InitPrice, GetCurrentPrice(), GetDiscPer(), config.TotalSupply, values.CurrentSupply, 
        values.TotalAmount, auction.GetBidders().length, IsEnded(), values.Completed);
    }
    
    function IsEnded() public view returns(bool){
        if (values.Ended == true)
            return true;
        
        uint256 price = GetCurrentPrice();
        if (price <= config.ResPrice)
            return true;
        
        uint256 supply = values.TotalAmount / price;
        if ((values.TotalAmount % price) > 0)
            supply += 1;
        
        if (supply >= config.TotalSupply)
            return true;
            
        return false;
    }
    
    function IsCompleted() external view returns(bool){
        return values.Completed;
    }
    
    function TokensOf(address _bidder) external view returns(uint256){
        return tokens[_bidder];
    }
    
    function BidOf(address _bidder) external view returns(uint256){
        return auction.GetAmount(_bidder);
    }
    
    function TransferTokens() external{
        if (tokens[msg.sender] == 0)
            return;
            
        IERC20 token = IERC20(config.TokenAddr);
        token.transfer(msg.sender, tokens[msg.sender]  * 10 ** 18);
        tokens[msg.sender] = 0;
    }
    
    function TransferFunds(address payable _recepient, uint256 amount) external{
        require(_owner == msg.sender, "Only owner can transfer funds");
        _recepient.transfer(amount);
    }
}