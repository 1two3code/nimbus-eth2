import
  std/[tables],
  NimQml,
  ../beacon_chain/rpc/beacon_rest_client,
  ../beacon_chain/spec/[datatypes, digest, helpers],
  ../beacon_chain/ssz/merkleization,
  ./objecttablemodel, ./utils

type
  SlotInfo* = object
    slot*: int
    proposer_index*: int
    block_root*: string

proc loadSlots*(client: RestClientRef, epoch: Epoch): seq[SlotInfo] {.raises: [Defect].} =
  var res: seq[SlotInfo]
  let proposers = try:
    (waitFor client.getProposerDuties(epoch)).data.data
  except Exception: # TODO chronos exceptions
    newSeq[RestProposerDuty](SLOTS_PER_EPOCH)

  for i in 0..<SLOTS_PER_EPOCH:
    let
      slot = epoch.compute_start_slot_at_epoch() + i
      block_root =
        try:
          let h = waitFor client.getBlockHeaders(some slot, none Eth2Digest)
          if h.data.data.header.message.slot == slot:
            toBlockLink(hash_tree_root(h.data.data.header.message))
          else:
            "N/A"
        except Exception as exc: # TODO chronos exceptions
          exc.msg
    res.add SlotInfo(
      slot: slot.int,
      proposer_index: proposers[i].validator_index.int,
      block_root: block_root
      )
  res

QtObject:
  type SlotList* = ref object of QAbstractTableModel
    # TODO this could be a generic ObjectTableModel, except generics + method don't work..
    data: ObjectTableModelImpl[SlotInfo]

  proc setup(self: SlotList) = self.QAbstractTableModel.setup

  proc delete(self: SlotList) =
    self.QAbstractTableModel.delete

  proc newSlotList*(data: seq[SlotInfo]): SlotList =
    new(result, delete)
    result.data = ObjectTableModelImpl[SlotInfo](items: data)
    result.setup

  method rowCount(self: SlotList, index: QModelIndex = nil): int =
    self.data.rowCount(index)

  method columnCount(self: SlotList, index: QModelIndex = nil): int =
    self.data.columnCount(index)

  method headerData*(self: SlotList, section: int, orientation: QtOrientation, role: int): QVariant =
    self.data.headerData(section, orientation, role)

  method data(self: SlotList, index: QModelIndex, role: int): QVariant =
    self.data.data(index, role)

  method roleNames(self: SlotList): Table[int, string] =
    self.data.roleNames()

  proc setNewData*(self: SlotList,  v: seq[SlotInfo]) =
    self.data.setNewData(self, v)

  proc sort*(self: SlotList, section: int) {.slot.} =
    self.data.sort(self, section)
