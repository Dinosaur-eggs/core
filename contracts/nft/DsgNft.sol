// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../governance/InitializableOwner.sol";
import "../interfaces/IDsgNft.sol";
import "../libraries/LibPart.sol";
import "../libraries/Random.sol";


contract DsgNft is IDsgNft, ERC721, InitializableOwner, ReentrancyGuard, Pausable
{
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _minters;
    using Strings for uint256;
    
    event Minted(
        uint256 indexed id,
        address to,
        uint256 level,
        uint256 power,
        string name,
        string res,
        address author,
        uint256 timestamp
    );

    event Upgraded(
        uint256 indexed nft1Id,
        uint256 nft2Id,
        uint256 newNftId,
        uint256 newLevel,
        uint256 timestamp
    );

    event RoyaltiesUpdated(uint256 indexed nftId, uint256 oldRoyalties, uint256 newRoyalties);

    mapping(uint256=>LibPart.NftInfo) private _nfts;

    /*
     *     bytes4(keccak256('getRoyalties(uint256)')) == 0xbb3bafd6
     *     bytes4(keccak256('sumRoyalties(uint256)')) == 0x09b94e2a
     *
     *     => 0xbb3bafd6 ^ 0x09b94e2a == 0xb282e1fc
     */
    bytes4 private constant _INTERFACE_ID_GET_ROYALTIES = 0xbb3bafd6;
    bytes4 private constant _INTERFACE_ID_ROYALTIES = 0xb282e1fc;

    int256 constant PERCENT_POINT = 10000;

    uint256 private _tokenId = 1000;

    uint256 public constant maxLevel = 6;

    string private _baseURIVar;

    IERC20 private _token;
    address public _feeWallet;

    uint256 private _upgradeFeeBase = 1**18;
    uint256[] private _levelBasePower = [1000, 2500, 6500, 14500, 35000, 90000];

    mapping(uint256 => LibPart.Part[])  private _royalties; //tokenId : LibPart.Part[]

    string private _name;
    string private _symbol;
    bool public canUpgrade;

    constructor() public ERC721("", "")
    {
       
    }
    
    function initialize(
        string memory name_, 
        string memory symbol_, 
        address feeToken, 
        address feeWallet_, 
        bool _canUpgrade,
        string memory baseURI_
    ) public {
            
        super._initialize();
        
        _registerInterface(_INTERFACE_ID_GET_ROYALTIES);
        _registerInterface(_INTERFACE_ID_ROYALTIES);

        _name = name_;
        _symbol = symbol_;
        _token = IERC20(feeToken);
        _feeWallet = feeWallet_;
        _baseURIVar = baseURI_;
        canUpgrade = _canUpgrade;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function setBaseURI(string memory uri) public onlyOwner {
        _baseURIVar = uri;
    }

    function baseURI() public view override returns (string memory) {
        return _baseURIVar;
    }

    function getUpgradeFeeBase() public view override returns (uint256) {
        return _upgradeFeeBase;
    }

    function setUpgradeFeeBase(uint256 fee) public onlyOwner {
        _upgradeFeeBase = fee;
    }

    function setFeeWallet(address feeWallet_) public onlyOwner {
        _feeWallet = feeWallet_;
    }

    function setFeeToken(address token) public onlyOwner {
        _token = IERC20(token);
    }

    function getFeeToken() public view override returns (address) {
        return address(_token);
    }

    function setCanUpgrade(bool newVal) public onlyOwner {
        canUpgrade = newVal;
    }

    function getNft(uint256 id) public view override returns (LibPart.NftInfo memory) {
        return _nfts[id];
    }

    function getRoyalties(uint256 tokenId) public view override returns (LibPart.Part[] memory) {
        return _royalties[tokenId];
    }

    function sumRoyalties(uint256 tokenId) public view override returns(uint256) {
        uint256 val;
        LibPart.Part[] memory parts = getRoyalties(tokenId);
        for(uint i = 0; i < parts.length; i++) {
            val += parts[i].value;
        }
        return val;
    }

    function updateRoyalties(uint256 tokenId, LibPart.Part[] memory parts) public {
        require(_nfts[tokenId].author == msg.sender, "not the author");

        uint256 old = sumRoyalties(tokenId);

        LibPart.Part[] storage np;
        for (uint i = 0; i < parts.length; i++) {
            np.push(parts[i]);
        }
        _royalties[tokenId] = np;

        emit RoyaltiesUpdated(tokenId, old, sumRoyalties(tokenId));
    }

    function updateRoyalty(uint256 tokenId, uint index, LibPart.Part memory newPart) public {
        require(_nfts[tokenId].author == msg.sender, "not the author");

        uint256 old = sumRoyalties(tokenId);

        _royalties[tokenId][index] = newPart;

        emit RoyaltiesUpdated(tokenId, old, sumRoyalties(tokenId));
    }

    function addRoyalty(uint256 tokenId, LibPart.Part memory newPart) public {
        require(_nfts[tokenId].author == msg.sender, "not the author");

        uint256 old = sumRoyalties(tokenId);

        _royalties[tokenId].push(newPart);

        emit RoyaltiesUpdated(tokenId, old, sumRoyalties(tokenId));
    }

    function _doMint(
        address to, string memory nftName, uint256 level, uint256 power, string memory res, address author
    ) internal returns(uint256) {
        _tokenId++;
        if(bytes(nftName).length == 0) {
            nftName = string(abi.encodePacked(name(), _tokenId.toString()));
        }

        _mint(to, _tokenId);

        LibPart.NftInfo memory nft;
        nft.name = nftName;
        nft.level = level;
        nft.power = power;
        nft.res = res;
        nft.author = author;

        _nfts[_tokenId] = nft;

        emit Minted(_tokenId, to, level, power, nftName, res, author, block.timestamp);
        return _tokenId;
    }

    function mint(
        address to, string memory nftName, uint level, uint256 power, string memory res, address author
    ) public override onlyMinter nonReentrant returns(uint256 tokenId){
        tokenId = _doMint(to, nftName, level, power, res, author);
    }

    function burn(uint256 tokenId) public override nonReentrant {
        address owner = ERC721.ownerOf(tokenId);
        require(_msgSender() == owner, "caller is not the token owner");

        _burn(tokenId);
    }

    function randomPower(uint256 level, uint256 seed ) internal view returns(uint256) {
        if (level == 1) {
            return _levelBasePower[level-1] + seed % 200;
        } else if (level == 2) {
            return _levelBasePower[level-1] + seed % 500;
        } else if (level == 3) {
            return _levelBasePower[level-1] + seed % 500;
        } else if (level == 4) {
            return _levelBasePower[level-1] + seed % 500;
        } else if (level == 5) {
            return _levelBasePower[level-1] + seed % 5000;
        }

        return _levelBasePower[6] + seed % 10000;
    }

    function getUpgradeFee(uint256 newLevel) public view returns (uint256) {
        return _upgradeFeeBase * _levelBasePower[newLevel];
    }

    function upgradeNft(uint256 nftId, uint256 materialNftId) public override nonReentrant whenNotPaused
    {
        require(canUpgrade, "CANT UPGRADE");
        LibPart.NftInfo memory nft = getNft(nftId);
        LibPart.NftInfo memory materialNft = getNft(materialNftId);

        require(nft.level == materialNft.level, "The level must be the same");
        require(nft.level < maxLevel, "Has reached the max level");

        _burn(nftId);
        _burn(materialNftId);

        uint256 newLevel = nft.level + 1;
        if (_upgradeFeeBase > 0) {
            uint256 fee = getUpgradeFee(newLevel);
            _token.transferFrom(_msgSender(), _feeWallet, fee);
        }

        uint256 seed = Random.computerSeed()/23;

        uint256 newId = _doMint(_msgSender(), nft.name, newLevel, randomPower(newLevel, seed), nft.res, nft.author);

        emit Upgraded(nftId, materialNftId, newId, newLevel, block.timestamp);
    }

    function getPower(uint256 tokenId) public view override returns (uint256) {
        return _nfts[tokenId].power;
    }

    function addMinter(address _addMinter) public onlyOwner returns (bool) {
        require(_addMinter != address(0), "Token: _addMinter is the zero address");
        return EnumerableSet.add(_minters, _addMinter);
    }

    function delMinter(address _delMinter) public onlyOwner returns (bool) {
        require(_delMinter != address(0), "Token: _delMinter is the zero address");
        return EnumerableSet.remove(_minters, _delMinter);
    }

    function getMinterLength() public view returns (uint256) {
        return EnumerableSet.length(_minters);
    }

    function isMinter(address account) public view returns (bool) {
        return EnumerableSet.contains(_minters, account);
    }

    function getMinter(uint256 _index) public view onlyOwner returns (address) {
        require(_index <= getMinterLength() - 1, "Token: index out of bounds");
        return EnumerableSet.at(_minters, _index);
    }

    // modifier for mint function
    modifier onlyMinter() {
        require(isMinter(msg.sender), "caller is not the minter");
        _;
    }
}
