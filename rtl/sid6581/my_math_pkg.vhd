library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package my_math_pkg is

    function sum_limit(i1, i2 : signed) return signed;
    function sub_limit(i1, i2 : signed) return signed;
end;

package body my_math_pkg is

    function sum_limit(i1, i2 : signed) return signed is
        variable o : signed(i1'range);
    begin
        assert i1'length = i2'length
            report "i1 and i2 should have the same length!"
            severity failure;
        o := i1 + i2;
        if (i1(i1'left) = i2(i2'left)) and (o(o'left) /= i1(i1'left)) then
            if i1(i1'left)='1' then
                o := to_signed(-(2**(o'length-1)), o'length);
            else
                o := to_signed(2**(o'length-1) - 1, o'length);
            end if;
        end if;
        return o;
    end function;

    function sub_limit(i1, i2 : signed) return signed is
        variable o : signed(i1'range);
    begin
        assert i1'length = i2'length
            report "i1 and i2 should have the same length!"
            severity failure;
        o := i1 - i2;
        if (i1(i1'left) /= i2(i2'left)) and (o(o'left) /= i1(i1'left)) then
            if i1(i1'left)='1' then
                o := to_signed(-(2**(o'length-1)), o'length);
            else
                o := to_signed(2**(o'length-1) - 1, o'length);
            end if;
        end if;
        return o;            
    end function;
end;
