#!/usr/bin/env python
from __future__ import division
from collections import defaultdict
from itertools import count
import math
import os
import struct
import sys

class BaseImage(object):
    _SIDE_TRACK_COUNT = 84
    _SPEED_TO_BYTE_LENGTH_LIST = [6250, 6666, 7142, 7692]
    _DEFAULT_SPEED_LIST = [3] * (17 - 0) * 2 + [2] * (24 - 17) * 2 + [1] * (30 - 24) * 2 + [0] * (42 - 30) * 2
    assert len(_DEFAULT_SPEED_LIST) == 84

    def __init__(self, gcr_half_track_dict):
        self.gcr_half_track_dict = gcr_half_track_dict

    def _getHalfTrackDataAndSpeed(self, half_track_number):
        try:
            speed = self._DEFAULT_SPEED_LIST[half_track_number]
        except IndexError:
            speed = None
        return self.gcr_half_track_dict.get(half_track_number, (None, speed))

    @classmethod
    def read(cls, istream):
        raise NotImplementedError

    def write(self, ostream):
        raise NotImplementedError

class I64(BaseImage):
    """
    file:
      84 * track_data + 84 * track_metadata
    track_data:
      0x2000 bytes whose bits represent magnetic flux changes
    track_metadata:
      speed + clock_count + track_length + previous_track_length_ratio + next_track_length_ratio
    speed (2 bits):
      Track speed zone (0, 1, 2, 3, 0 being slowest).
      Only intended to be used to reconstruct G64 image.
    clock_count (14 bits):
      The number, minus 32, of 16MHz clock pulses a "1" bit lasts.
      Stored as fixed-point: 6 bits for integer part followed by 8 bits for fractional part.
    track_length (16 bits):
      The number of bytes in that track.
    *_track_length_ratio (16 bits each)
      Fixed-point ratio between this track and...
      previous_*: the one with an immediately inferior track number
      next_*: the one with an immediately superior track number
    """

    # Fixed values (drive design)
    _BASE_CLOCK_FREQUENCY = 16e6 # Hz
    _SPINDLE_ROTATION_FREQUENCY = 5 # Hz, 300rpm = 5Hz
    _TIME_DOMAIN_FILTER_RESISTOR = 22 # kOhm +/- 5%
    _TIME_DOMAIN_FILTER_CAPACITOR = 330 # pF +/- 5%
    _TIME_DOMAIN_FILTER_K = 0.37 # from Fairchild 9602 datasheet, page 5 figure 6
    _TIME_DOMAIN_FILTER_PULSE_WIDTH = (
        _TIME_DOMAIN_FILTER_K *
        _TIME_DOMAIN_FILTER_RESISTOR *
        _TIME_DOMAIN_FILTER_CAPACITOR *
        (1 + 1 / _TIME_DOMAIN_FILTER_RESISTOR)
    ) # ns, +/- 10%, formula from Fairchild 9602 datasheet
    # XXX: Taking typical values (so ignoring component precision)
    _TIME_DOMAIN_FILTER_PULSE_BASE_CLOCK_WIDTH = _BASE_CLOCK_FREQUENCY * (_TIME_DOMAIN_FILTER_PULSE_WIDTH * 1e-9)
    # At the slowest speed (zone 0), it takes 32 clock cycles to shift a 1 and 64 to shift a 0.
    # This is because all a magnetic head can read is a flux change (for a 1).
    # Absence of flux change is handled as a timeout, so it is longer - twice longer in this drive's case.
    _ONE_SHIFT_CLOCK_CYCLE_COUNT = 32
    _ZERO_SHIFT_CLOCK_CYCLE_COUNT = 64
    # Time domain pulse must be longer that a "1", but shorter than a "0".
    # In reality, given component values this is around 45 clock cycles. At +/- 20%
    # (10% from 6902 chip, 5% from capacitor, 5% from resistor), this is from 36 to 54,
    # so this assertion is more about documenting circuit and as a rough sanity check
    # than an expected error case.
    assert _ONE_SHIFT_CLOCK_CYCLE_COUNT < _TIME_DOMAIN_FILTER_PULSE_BASE_CLOCK_WIDTH < _ZERO_SHIFT_CLOCK_CYCLE_COUNT, _TIME_DOMAIN_FILTER_PULSE_BASE_CLOCK_WIDTH
    del _BASE_CLOCK_FREQUENCY
    del _SPINDLE_ROTATION_FREQUENCY
    del _TIME_DOMAIN_FILTER_RESISTOR
    del _TIME_DOMAIN_FILTER_CAPACITOR
    del _TIME_DOMAIN_FILTER_K
    del _TIME_DOMAIN_FILTER_PULSE_WIDTH

    # 16 - x: number of 16MHz clock pulses needed to overflow UE6 for speed zone "x"
    # 2: after 2 UE6 overflows a bit is clocked in/out of the bit shift registers by UF4
    _STANDARD_ONE_DELAY_LIST = tuple([(16 - x) * 2 for x in (0, 1, 2, 3)])
    _STANDARD_ZERO_DELAY_LIST = tuple([(16 - x) * 4 for x in (0, 1, 2, 3)])
    _MIN_ONE_DELAY = math.ceil(_TIME_DOMAIN_FILTER_PULSE_BASE_CLOCK_WIDTH)

    _TRACK_LENGTH = 2 ** max(BaseImage._SPEED_TO_BYTE_LENGTH_LIST).bit_length()
    assert _TRACK_LENGTH == 0x2000, _TRACK_LENGTH
    _BLANK_TRACK = '\x00' * _TRACK_LENGTH
    _METADATA_BLOCK_OFFSET = _TRACK_LENGTH * BaseImage._SIDE_TRACK_COUNT
    _FILE_SIZE = _METADATA_BLOCK_OFFSET + 0x400 # Add one LBA for metadata: 84 * 4 < 0x200

    @classmethod
    def read(cls, istream):
        istream.seek(cls._METADATA_BLOCK_OFFSET)
        track_metadata_list = [struct.unpack('>BBHHH', istream.read(8)) for _ in range(cls._SIDE_TRACK_COUNT)]
        istream.seek(0)
        gcr_half_track_dict = {}
        for half_track_number, (track_speed_and_delay_integer, _, track_length, _, _) in enumerate(track_metadata_list):
            track = istream.read(cls._TRACK_LENGTH)
            if track != cls._BLANK_TRACK:
                gcr_half_track_dict[half_track_number] = (track[:track_length], track_speed_and_delay_integer >> 6)
        return cls(gcr_half_track_dict)

    def write(self, ostream):
        track_metadata_list = []
        next_track_length = previous_track_length = None
        for half_track_number in range(self._SIDE_TRACK_COUNT):
            track, speed = self._getHalfTrackDataAndSpeed(half_track_number)
            if track:
                track_length = len(track)
                assert track_length <= self._TRACK_LENGTH, (half_track_number, track_length)
            else:
                track_length = len(self._BLANK_TRACK) if previous_track_length is None else previous_track_length
                track = self._BLANK_TRACK
            assert next_track_length in (track_length, None), (half_track_number, next_track_length, track_length)
            delay = self._SPEED_TO_BYTE_LENGTH_LIST[speed] / track_length * self._STANDARD_ZERO_DELAY_LIST[speed]
            assert self._TIME_DOMAIN_FILTER_PULSE_BASE_CLOCK_WIDTH < delay < self._STANDARD_ONE_DELAY_LIST[speed] + self._STANDARD_ZERO_DELAY_LIST[speed], (half_track_number, delay, speed)
            delay_integer, delay_fractional = divmod(delay, 1)
            if previous_track_length is None:
                previous_track_length = track_length
            next_track, _ = self._getHalfTrackDataAndSpeed(half_track_number + 1)
            next_track_length = len(next_track) if next_track else track_length
            track_metadata_list.append(struct.pack(
                '>BBHHH',
                speed << 6 | (int(delay_integer) - self._ONE_SHIFT_CLOCK_CYCLE_COUNT),
                int(delay_fractional * 256),
                track_length,
                int(round(previous_track_length / track_length * 2**15)),
                int(round(next_track_length / track_length * 2**15)),
            ))
            previous_track_length = track_length
            ostream.write(track)
            ostream.write('\x00' * (self._TRACK_LENGTH - len(track)))
        assert self._METADATA_BLOCK_OFFSET == ostream.tell()
        ostream.write(''.join(track_metadata_list))
        ostream.write('\x00' * (self._FILE_SIZE - ostream.tell()))

class G64(BaseImage):
    _MAGIC = 'GCR-1541\x00'

    @classmethod
    def read(cls, istream):
        magic = istream.read(len(cls._MAGIC))
        assert magic == cls._MAGIC, repr(magic)
        track_count, max_track_length = struct.unpack('<BH', istream.read(3))
        track_data_offset_list = []
        track_speed_offset_list = []
        for offset_list in (
            track_data_offset_list,
            track_speed_offset_list,
        ):
            for _ in range(track_count):
                offset_list.append(struct.unpack('<I', istream.read(4))[0])
        gcr_half_track_dict = {}
        for half_track_number, track_data_offset in enumerate(track_data_offset_list):
            if not track_data_offset:
                continue
            istream.seek(track_data_offset)
            track_length = struct.unpack('<H', istream.read(2))[0]
            assert track_length <= max_track_length, (half_track_number, track_length)
            gcr_half_track_dict[half_track_number] = [istream.read(track_length), None]
        # XXX: no speed support, just check the value is standard
        for half_track_number, track_speed_offset in enumerate(track_speed_offset_list):
            half_track_length = len(gcr_half_track_dict.get(half_track_number, ''))
            if not half_track_length:
                continue
            if track_speed_offset > 3:
                istream.seek(track_speed_offset)
                track_speed_set = set()
                speed_data = [
                    struct.unpack('B', x)[0]
                    for x in istream.read((half_track_length + 3) // 4)
                ]
                for data_byte_index in range(half_track_length):
                    speed_byte_index, half_shift = divmod(data_byte_index, 4)
                    track_speed_set.add((speed_data[speed_byte_index] >> (8 - half_shift * 2)) & 0x3)
                if len(track_speed_set):
                    print 'Warning half track %i: multiple speeds used: %r' % (half_track_number, track_speed_set)
                    track_speed = max(track_speed_set)
            else:
                track_speed = track_speed_offset
            gcr_half_track_dict[half_track_number][1] = track_speed
        return cls(gcr_half_track_dict)

    def write(self, ostream):
        ostream.write(self._MAGIC)
        track_count = self._SIDE_TRACK_COUNT
        assert len(self.gcr_half_track_dict) <= track_count
        max_track_length = 7928
        assert max(len(x) for x, _ in self.gcr_half_track_dict.values()) <= max_track_length, ([len(x) for x, _ in self.gcr_half_track_dict.values()], max_track_length)
        ostream.write(struct.pack('<BH', track_count, max_track_length))
        base_offset = current_offset = ostream.tell() + 4 * 2 * track_count
        half_track_offset_list = []
        speed_list = []
        for half_track_number in range(track_count):
            track_data, track_speed = self._getHalfTrackDataAndSpeed(half_track_number)
            if track_data:
                offset = current_offset
                current_offset += max_track_length + 2 # +2 for the length bytes header
                half_track_offset_list.append((half_track_number, offset))
            else:
                speed = 0 # Not really meaningful ?
                offset = 0
            speed_list.append(track_speed)
            ostream.write(struct.pack('<I', offset))
        for speed in speed_list:
            ostream.write(struct.pack('<I', speed))
        assert ostream.tell() == base_offset, (ostream.tell(), base_offset)
        for half_track_number, offset in half_track_offset_list:
            track_data, _ = self.gcr_half_track_dict[half_track_number]
            assert offset == ostream.tell(), (half_track_number, offset, ostream.tell())
            ostream.write(struct.pack('<H', len(track_data)))
            ostream.write(track_data)
            if len(track_data) < max_track_length:
                # XXX: vice is not consistent in post-track content: new disks contain
                # 0x55, modified tracks contain 0x00. 0x55 is already naturally present
                # and is valid GCR, so use this.
                ostream.write('\x55' * (max_track_length - len(track_data)))

MASK_LIST = (0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01)
def toBitString(byte_string):
    # XXX: ultra-low-tech, takes ~8 times the memory, but simple
    result = []
    append = result.append
    for data_byte in byte_string:
        data_byte = ord(data_byte)
        append(''.join('1' if data_byte & mask else '0' for mask in MASK_LIST))
    return ''.join(result)

SHIFT_LIST = (7, 6, 5, 4, 3, 2, 1, 0)
def toByteString(bit_string):
    result = []
    append = result.append
    while bit_string:
        one_byte, bit_string = bit_string[:8], bit_string[8:]
        if len(one_byte) != 8:
            one_byte += '1' * (8 - len(one_byte))
        append(chr(sum(int(x) << y for x, y in zip(one_byte, SHIFT_LIST))))
    return ''.join(result)

class D64(BaseImage):
    _TRACK_SECTOR_COUNT_LIST = [21] * (17 - 0) + [19] * (24 - 17) + [18] * (30 - 24) + [17] * (42 - 30)
    _POST_DATA_GAP_LENGTH_LIST = [8] * (17 - 0) + [17] * (24 - 17) + [12] * (30 - 24) + [9] * (42 - 30)
    # BAM sector offset 162 & 163 have the disk ID
    _ID_OFFSET = 0x165a2
    _GCR_SYNC = '\xff' * 5
    _GCR_GAP = '\x55'
    _GCR_LIST = [
        0b01010, 0b01011,
        0b10010, 0b10011,
        0b01110, 0b01111,
        0b10110, 0b10111,
        0b01001, 0b11001,
        0b11010, 0b11011,
        0b01101, 0b11101,
        0b11110, 0b10101,
    ]
    _GCR_DICT = {y: x for x, y in enumerate(_GCR_LIST)}
    _SYNC_BIT_STRING = '1' * 10
    _EMPTY_BLOCK = '\x00' * 256

    # Error block codes
    _STATUS_OK = 0
    _STATUS_NO_HEADER = 20
    _STATUS_NO_SYNC = 21
    _STATUS_NO_DATA = 22
    _STATUS_BAD_DATA = 23
    _STATUS_BAD_HEADER = 27
    _STATUS_ID_MISMATCH = 29

    @classmethod
    def _gcr_encode(cls, data):
        gcr_mask = [2 ** x - 1 for x in range(1, 9)]
        result = []
        gcr = 0
        gcr_bitcount = 0
        gcr_list = cls._GCR_LIST
        #import pdb; pdb.set_trace()
        for data_byte in data:
            data_byte = ord(data_byte)
            gcr <<= 10
            gcr += (gcr_list[data_byte >> 4] << 5) + gcr_list[data_byte & 0xf]
            gcr_bitcount += 10
            while gcr_bitcount >= 8:
                gcr_bitcount -= 8
                result.append(chr((gcr >> gcr_bitcount) & 0xff))
            gcr &= gcr_mask[gcr_bitcount]
        assert not gcr_bitcount, (gcr_bitcount, gcr, len(data), repr(data), repr(''.join(result)))
        return ''.join(result)

    @classmethod
    def _gcr_decode(cls, data):
        gcr_mask = [2 ** x - 1 for x in range(10)]
        result = []
        gcr = 0
        gcr_bitcount = 0
        gcr_dict = cls._GCR_DICT
        for gcr_byte in data:
            gcr_byte = ord(gcr_byte)
            gcr <<= 8
            gcr += gcr_byte
            gcr_bitcount += 8
            while gcr_bitcount >= 10:
                gcr_bitcount -= 10
                result.append(chr(
                    (gcr_dict.get((gcr >> (gcr_bitcount + 5)) & 0x1f, 0) << 4) +
                    gcr_dict.get((gcr >> gcr_bitcount) & 0x1f, 0),
                ))
            gcr &= gcr_mask[gcr_bitcount]
        return ''.join(result)

    @classmethod
    def read(cls, istream):
        istream.seek(cls._ID_OFFSET)
        disk_id = ''.join(reversed(istream.read(2)))
        disk_id_sum = ord(disk_id[0]) ^ ord(disk_id[1])
        bad_disk_id = disk_id[0] + chr(ord(disk_id[1]) ^ 1)
        bad_disk_id_sum = ord(bad_disk_id[0]) ^ ord(bad_disk_id[1])
        istream.seek(0, 2)
        track_count, error_block_offset = {
            174848: (35, None),
            175531: (35, 174848),
            196608: (40, None),
            197376: (40, 196608),
            205312: (42, None),
            206114: (42, 205312),
            # D71
            349696: (70, None),
            351062: (70, 349696),
        }[istream.tell()]
        if track_count > 42:
            print 'Warning: no double-sided disk support yet, ignoring tracks above 35'
            track_count = 35
        if error_block_offset:
            istream.seek(error_block_offset)
            error_list = [
                [
                    ord(istream.read(1))
                    for _ in range(cls._TRACK_SECTOR_COUNT_LIST[track_number])
                ]
                for track_number in range(track_count)
            ]
        else:
            error_list = [
                [
                    cls._STATUS_OK
                    for _ in range(cls._TRACK_SECTOR_COUNT_LIST[track_number])
                ]
                for track_number in range(track_count)
            ]
        istream.seek(0)
        gcr_half_track_dict = {}
        for track_number in range(track_count):
            track_error_list = error_list[track_number]
            if cls._STATUS_NO_SYNC in track_error_list:
                if len(set(track_error_list)) == 1:
                    # No sync on whole track ? leave it blank
                    continue
                print 'Warning: image contains tracks with a mix of "NO SYNC" and other block statuses, ignoring "NO SYNC"'
            gcr_track = []
            for block_number in range(cls._TRACK_SECTOR_COUNT_LIST[track_number]):
                block_error = track_error_list[block_number]
                block_data = istream.read(256)
                assert len(block_data) == 256, (track_number, block_number)
                data_checksum = 0
                if block_error == cls._STATUS_BAD_DATA:
                    data_checksum += 1
                if block_error == cls._STATUS_ID_MISMATCH:
                    block_disk_id = bad_disk_id
                    block_disk_id_sum = bad_disk_id_sum
                else:
                    block_disk_id = disk_id
                    block_disk_id_sum = disk_id_sum
                for data_byte in block_data:
                    data_checksum ^= ord(data_byte)
                gap_length = cls._POST_DATA_GAP_LENGTH_LIST[track_number]
                gcr_track.append(
                    cls._GCR_SYNC + cls._gcr_encode(
                        ('\x00' if block_error == cls._STATUS_NO_HEADER else '\x08') +
                        chr(
                            (track_number + 1) ^
                            block_number ^
                            block_disk_id_sum ^
                            (1 if block_error == cls._STATUS_BAD_HEADER else 0)
                        ) +
                        chr(block_number) +
                        chr(track_number + 1) +
                        block_disk_id +
                        '\x0f\x0f', # To get to a multiple of 4 bytes for GCR encoding
                    ) + cls._GCR_GAP * 9 +
                    cls._GCR_SYNC + cls._gcr_encode(
                        ('\x00' if block_error == cls._STATUS_NO_DATA else '\x07') +
                        block_data +
                        chr(data_checksum) +
                        # XXX: VICE uses 0x00 padding
                        '\x00\x00', #'\x0f\x0f', # To get to a multiple of 4 bytes for GCR encoding
                    ) + cls._GCR_GAP * gap_length,
                )
            # Double is the new half.
            half_track_number = track_number * 2
            gcr_track = ''.join(gcr_track)
            speed = cls._DEFAULT_SPEED_LIST[half_track_number]
            track_usable_length = cls._SPEED_TO_BYTE_LENGTH_LIST[speed]
            if len(gcr_track) < track_usable_length:
                gcr_track += '\x55' * (track_usable_length - len(gcr_track))
            gcr_half_track_dict[half_track_number] = (gcr_track, speed)
        return cls(gcr_half_track_dict)

    def write(self, ostream):
        for half_track_number in range(self._SIDE_TRACK_COUNT):
            if half_track_number & 1:
                continue
            # Half is the new double.
            track_number = half_track_number // 2
            track_sector_count = self._TRACK_SECTOR_COUNT_LIST[track_number]
            track_gcr_data, speed = self._getHalfTrackDataAndSpeed(half_track_number)
            if not track_gcr_data:
                ostream.write(self._EMPTY_BLOCK * track_sector_count)
                continue
            assert speed == self._DEFAULT_SPEED_LIST[half_track_number], 'D64 cannot contain non-standard speed tracks: half-track %i speed %i, standard speed %i' % (
                half_track_number,
                speed,
                self._DEFAULT_SPEED_LIST[half_track_number],
            )
            # Make track easy to manipulate at individual bit level.
            track_gcr_bit_string = toBitString(track_gcr_data.rstrip('\x00'))
            # Align to beginning of first sync mark.
            if self._SYNC_BIT_STRING not in track_gcr_bit_string:
                print 'Warning half track %i: no sync mark, assuming empty' % half_track_number
                ostream.write(self._EMPTY_BLOCK * track_sector_count)
                continue
            first_sync_mark_pos = track_gcr_bit_string.index(self._SYNC_BIT_STRING)
            track_gcr_bit_string = track_gcr_bit_string[first_sync_mark_pos:] + track_gcr_bit_string[:first_sync_mark_pos]
            # Split on sync marks.
            between_sync_chunk_list = [x.strip('1') for x in track_gcr_bit_string.split(self._SYNC_BIT_STRING)]
            decoded_chunk_list = []
            for between_sync_chunk in between_sync_chunk_list:
                if not between_sync_chunk:
                    continue
                between_sync_chunk = toByteString(between_sync_chunk)
                decoded_chunk_list.append(self._gcr_decode(between_sync_chunk))
            # If first chunk is of data type, move it at the end of the list (hopefully behind its header)
            if decoded_chunk_list[0][0] == '\x07':
                decoded_chunk_list.append(decoded_chunk_list.pop(0))
            disk_dict = defaultdict(lambda: defaultdict(list))
            decoded_chunk_list.reverse() # Because it's faster to pop from end of list
            while decoded_chunk_list:
                decoded_chunk = decoded_chunk_list.pop()
                stripped_decoded_chunk = decoded_chunk.rstrip('\x0f')
                if stripped_decoded_chunk[0] != '\x08' or len(stripped_decoded_chunk) < 6:
                    print 'Warning half track %i: not a (complete) block header: %r' % (half_track_number, decoded_chunk)
                    continue
                _, checksum, block_number, block_track_number, disk_id1, disk_id2 = struct.unpack('BBBBcc', stripped_decoded_chunk[:6])
                if block_track_number != track_number + 1:
                    print 'Warning half track %i: god a block claiming to be from track %i' % (half_track_number, track_number + 1)
                    continue
                if checksum != block_number ^ block_track_number ^ ord(disk_id1) ^ ord(disk_id2):
                    print 'Warning half track %i: bad header checksum: %02x != %02x + %02x + %02x + %02x' % (half_track_number, checksum, block_number, block_track_number, ord(disk_id1), ord(disk_id2))
                    continue
                decoded_chunk = decoded_chunk_list.pop()
                if decoded_chunk[0] != '\x07' or len(decoded_chunk) < 258:
                    print 'Warning half track %i: not a (complete) data block: %r' % (half_track_number, decoded_chunk)
                    continue
                data_checksum = ord(decoded_chunk[257])
                data = decoded_chunk[1:257]
                recomputed_data_checksum = 0
                for data_byte in data:
                    recomputed_data_checksum ^= ord(data_byte)
                if recomputed_data_checksum & 0xff != data_checksum:
                    print 'Warning half track %i: bad data checksum: %02x != %02x' % (half_track_number, data_checksum, recomputed_data_checksum)
                    continue
                disk_dict[disk_id1 + disk_id2][block_number].append(data)
            # If disk was reformated, it is possible a few headers from previous disk survived in the gaps.
            # Pick the id which has most sectors. (one must be the clearly most common)
            if not disk_dict:
                print 'Warning half track %i: no valid block found, assuming empty' % half_track_number
                ostream.write(self._EMPTY_BLOCK * track_sector_count)
                continue
            block_dict = sorted(disk_dict.values(), key=lambda x: len(x))[-1]
            block_list = []
            for block_id in range(track_sector_count):
                block, = block_dict.get(block_id, (self._EMPTY_BLOCK, )) # Detect aliased blocks
                block_list.append(block)
            ostream.write(''.join(block_list))

EXTENSION_TO_CLASS = {
    '.d64': D64,
    '.d71': D64,
    '.g64': G64,
    '.i64': I64,
}
def main(infile_name, outfile_name):
    if os.path.exists(outfile_name):
        raise ValueError('Not overwriting %r' % outfile_name)
    infile_class = EXTENSION_TO_CLASS[os.path.splitext(infile_name)[1].lower()]
    outfile_class = EXTENSION_TO_CLASS[os.path.splitext(outfile_name)[1].lower()]
    with open(infile_name, 'r') as infile:
        try:
            with open(outfile_name, 'w') as outfile:
                outfile_class(infile_class.read(infile).gcr_half_track_dict).write(outfile)
        except Exception:
            os.unlink(outfile_name)
            raise

if __name__ == '__main__':
    main(*sys.argv[1:])
