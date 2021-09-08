// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../governance/InitializableOwner.sol";
import "../interfaces/IDsgNft.sol";
import "../libraries/Random.sol";


contract MysteryBox is ERC721, InitializableOwner {

    struct BoxFactory {
        uint256 id;
        string name;
        IDsgNft nft;
        uint256 limit; //0 unlimit
        uint256 minted;
        address author;
        string resPrefix; //If the resNumBegin = resNumEnd, resName will be resPrefix
        uint resNumBegin;
        uint resNumEnd;
        uint256 createdTime;
    }

    struct BoxView {
        uint256 id;
        uint256 factoryId;
        string name;
        address nft;
        uint256 limit; //0 unlimit
        uint256 minted;
        address author;
    }

    event NewBoxFactory(
        uint256 indexed id,
        string name,
        address nft,
        uint256 limit,
        address author,
        string resPrefix,
        uint resNumBegin,
        uint resNumEnd,
        uint256 createdTime
    );

    event OpenBox(uint256 indexed id, address indexed nft, uint256 boxId, uint256 tokenId);
    event Minted(uint256 indexed id, uint256 indexed factoryId, address to);

    uint256 private _boxFactoriesId = 0;
    uint256 private _boxId = 1e3;

    string private _baseURIVar;

    mapping(uint256 => uint256) private _boxes; //boxId: BoxFactoryId
    mapping(uint256 => BoxFactory) private _boxFactories;

    uint256[] private _levelBasePower = [1000, 2500, 6500, 14500, 35000, 90000];

    string private _name;
    string private _symbol;

    constructor() public ERC721("", "") {
    }

    function initialize(string memory uri) public {
        super._initialize();

        _levelBasePower = [1000, 2500, 6500, 14500, 35000, 90000];
        _boxId = 1e3;

        _baseURIVar = uri;

        _name = "DsgMysteryBox";
        _symbol = "DsgBox";
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

    function randomRes(uint256 seed, string memory prefix, uint numBegin, uint numEnd) internal pure returns(string memory res) {
        uint256 num = uint256(numEnd - numBegin);
        if(num == 0) {
            return prefix;
        }

        num = seed / 3211 % (num+1) + uint256(numBegin);
        res = string(abi.encodePacked(prefix, num.toString()));
    }

    function addBoxFactory(
        string memory name,
        IDsgNft nft,
        uint256 limit,
        address author,
        string memory resPrefix,
        uint resNumBegin,
        uint resNumEnd
    ) public onlyOwner returns (uint256) {
        _boxFactoriesId++;

        BoxFactory memory box;
        box.id = _boxFactoriesId;
        box.name = name;
        box.nft = nft;
        box.limit = limit;
        box.resPrefix = resPrefix;
        box.resNumBegin = resNumBegin;
        box.resNumEnd = resNumEnd;
        box.author = author;
        box.createdTime = block.timestamp;

        _boxFactories[_boxFactoriesId] = box;

        emit NewBoxFactory(
            _boxFactoriesId,
            name,
            address(nft),
            limit,
            author,
            resPrefix,
            resNumBegin,
            resNumEnd,
            block.timestamp
        );
        return _boxFactoriesId;
    }

    function mint(address to, uint256 factoryId, uint256 amount) public onlyOwner {
        BoxFactory storage box = _boxFactories[factoryId];
        require(address(box.nft) != address(0), "box not found");
        
        if(box.limit > 0) {
            require(box.limit - box.minted >= amount, "Over the limit");
        }
        box.minted = box.minted + amount;

        for(uint i = 0; i < amount; i++) {
            _boxId++;
            _mint(to, _boxId);
            _boxes[_boxId] = factoryId;
            emit Minted(_boxId, factoryId, to);
        }
    }

    function burn(uint256 tokenId) public {
        address owner = ERC721.ownerOf(tokenId);
        require(_msgSender() == owner, "caller is not the box owner");

        delete _boxes[tokenId];
        _burn(tokenId);
    }

    function getFactory(uint256 factoryId) public view
    returns (BoxFactory memory)
    {
        return _boxFactories[factoryId];
    }

    function getBox(uint256 boxId)
    public
    view
    returns (BoxView memory)
    {
        uint256 factoryId = _boxes[boxId];
        BoxFactory memory factory = _boxFactories[factoryId];

        return BoxView({
            id: boxId,
            factoryId: factoryId,
            name: factory.name,
            nft: address(factory.nft),
            limit: factory.limit,
            minted: factory.minted,
            author: factory.author
        });
    }

    // 50 30 15 4 0.9 0.1
    function getLevel(uint256 seed) internal pure returns(uint256) {
        uint256 val = seed / 8897 % 1000;
        if(val <= 5000) {
            return 1;
        } else if (val < 8000) {
            return 2;
        } else if (val < 9500) {
            return 3;
        } else if (val < 9900) {
            return 4;
        } else if (val < 9990) {
            return 5;
        }
        return 6;
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

    function openBox(uint256 boxId) public {
        require(isContract(msg.sender) == false, "Prohibit contract calls");

        uint256 factoryId = _boxes[boxId];
        BoxFactory memory factory = _boxFactories[factoryId];
        burn(boxId);

        uint256 seed = Random.computerSeed();

        string memory resName = randomRes(seed, factory.resPrefix, factory.resNumBegin, factory.resNumEnd);

        uint256 level = getLevel(seed);
        uint256 power = randomPower(level, seed);
        uint256 tokenId = factory.nft.mint(_msgSender(), "", level, power, resName, factory.author);

        emit OpenBox(boxId, address(factory.nft), boxId, tokenId);
    }

    function isContract(address addr) internal view returns (bool) {
        uint size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }
}
