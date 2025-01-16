
-- Depth First Search Module (DFS)
------------------------------------------------------------------------------------------------------------------------------------------------------

-- Brief explanation of the module:

-- Depth First Search module can store and traverse over a directed acyclic graph (DAG) having a user defined maximum node number. 
-- Module sends visited node info to the output port at every clock cycle. 
-- Latency of "traverse" start" signal to valid "visited" node info at the output port is 4 clock cycles. 
-- Adjacent nodes of a visited node is stored in a stack at every clock cycle.

-- Module holds graph information in node value map, node adjacency list and node adjacency number arrays. 
-- Each node in the graph is assigned to a specific index number. To access a node in the graph, assigned index values are used.
-- Adjacency list of each node is represented as 2D array containing values of adjacent nodes.
-- Module can store values of each node and adjacencies of each node at every clock cycle.

-- Module functional summary:
    -- Constructing graph with input node data.
    -- Traversing over the graph.
    -- Storing adjacent nodes in a stack.
    -- Sending results. 
------------------------------------------------------------------------------------------------------------------------------------------------------ 

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity dfs is
    generic (   MAX_NODE_NUM    : integer range 0 to 64:=64;                -- maximum node number of the graph
                VALUE_WIDTH     : integer range 0 to 7:=7                   -- width of the value vector that represents the value of a node 
            );
            
    Port    (   CLK         : in std_logic;                                 -- module clock signal
                RST         : in std_logic;                                 -- module reset signal
                DATA        : in std_logic_vector(VALUE_WIDTH-1 downto 0);  -- data input representing node values 
                NODE_IN     : in std_logic;                                 -- node data ready signal
                ADJ_IN      : in std_logic;                                 -- node adjacency data ready signal
                TRAVERSE    : in std_logic;                                 -- graph traversing start signal 
                VISITED     : out std_logic_vector(VALUE_WIDTH-1 downto 0); -- visited node value
                COMPLETE    : out std_logic                                 -- graph traversing completed signal
            );
end dfs;

architecture behavioral of dfs is

-- Node value map array that assigns a specific index for each node.
-- ( node values: 1 to MAX_NODE_NUM, node indices: 1 to MAX_NODE_NUM )  (index 0 and value 0 is not used)
type node_val_map_array is array(0 to MAX_NODE_NUM) of integer range 0 to MAX_NODE_NUM; 
signal node_val_map: node_val_map_array; -- array mapping node values to indices

-- Node adjacency list array that holds adjacent node values of each node in the graph.
-- ( node indices: 1 - MAX_NODE_NUM, adjacent nodes: 0 to MAX_NODE_NUM-2, node values: 1 to MAX_NODE_NUM )  
type node_adj_array is array(0 to MAX_NODE_NUM, 0 to MAX_NODE_NUM-2) of integer range 0 to MAX_NODE_NUM; 
signal node_adj: node_adj_array; 

--- Node adjacency number array that holds number of adjacent nodes of each node in the graph.
type node_adj_num_array is array(0 to MAX_NODE_NUM) of integer range 0 to MAX_NODE_NUM-1;  
signal node_adj_num: node_adj_num_array; 


-- Graph node info store process signals
signal ind_1:           integer range 0 to MAX_NODE_NUM:=0; 
signal ind_2:           integer range 0 to MAX_NODE_NUM:=0; 
signal adj_ind:         integer range 0 to MAX_NODE_NUM-1:=0; 

-- Source, destination and visited nodes 
signal source_node:     integer range 0 to MAX_NODE_NUM;
signal target_node:     integer range 0 to MAX_NODE_NUM;
signal visited_node:    integer range 0 to MAX_NODE_NUM;  

-- Graph traverse controller process signals
signal cnt_state:       std_logic:='0'; 
signal source_index:    integer range 0 to MAX_NODE_NUM;
signal traverse_en:     std_logic:='0';                    

-- Graph traverse process signals 
signal traverse_type:   std_logic:='0'; 
signal adj_case:        std_logic_vector(1 downto 0):="00";
signal register_en:     std_logic:='0';                     
signal stack_en:        std_logic:='0';   
signal first_node:      std_logic:='0';
signal latency_cycle:   std_logic:='0';    
signal index:           integer range 0 to MAX_NODE_NUM;   
signal node_value:      integer range 0 to MAX_NODE_NUM;
signal stacked_node:    integer range 0 to MAX_NODE_NUM;
signal adj_num:         integer range 0 to MAX_NODE_NUM-1;
        
-- Stack array contaning values of stacked nodes 
type stack_array is array (0 to MAX_NODE_NUM-1) of integer range 0 to MAX_NODE_NUM; 
signal stack:           stack_array ;                      

begin

-- Receive graph data / Construct graph --
-- This process receives graph data as a sequence of node values and node adjacencies.
-- Master module (module that controls DFS module) sets node value on DATA port and asserts NODE_IN signal. 
-- At the next clock cycle, master module sets adjacent node value on DATA port and asserts ADJ_IN signal.
-- At every clock cycle, master module continues to send adjacent node values until the last adjacent node is sent.
store_graph:process(CLK) 
variable value:         integer range 0 to MAX_NODE_NUM;
begin

    if rising_edge(CLK) then
        
        if(RST='1') then
        
            -- Initializing node value, node adjacency list and node value map arrays
            for i in 0 to MAX_NODE_NUM loop
                
                node_adj_num(i) <= 0;
                node_val_map(i) <= 0;
                
                for j in 0 to MAX_NODE_NUM-2 loop
                    node_adj(i,j) <= 0;
                end loop;
                
            end loop; 
            
            ind_1       <= 0;
            ind_2       <= 0;
            adj_ind     <= 0;
            
        else
            
            -- Inserting node value data
            if(NODE_IN='1') then
                value                       := to_integer(unsigned(DATA));
                node_val_map(value)         <= ind_1;
                ind_1                       <= ind_1 + 1;
                ind_2                       <= ind_1;
                adj_ind                     <= 0;
            end if;
            
            -- Inserting adjacency data
            if(ADJ_IN='1') then
                value                       := to_integer(unsigned(DATA));
                node_adj(ind_2,adj_ind)     <= value;
                node_adj_num(ind_2)         <= adj_ind + 1;
                adj_ind                     <= adj_ind + 1;
            end if;
        
        end if; 
               
    end if;
end process store_graph;


-- Controlling graph traverse  / Sending visited nodes to the output data port --
-- This process checks for the traverse start indicator.
-- Visited nodes are sent to the output port at every clock cycle. 
graph_traverse_controller:process(CLK) 
begin

    if rising_edge(CLK) then
        
        if(RST='1') then
            cnt_state   <= '0';
            COMPLETE    <= '0';
            VISITED     <= std_logic_vector(to_unsigned(0,VALUE_WIDTH)); 
            traverse_en <= '0';
            
        else
        
            case (cnt_state) is
            
                when '0' =>
                
                    traverse_en        <= '0';
                    
                    -- Starting graph traverse
                    if(TRAVERSE='1') then
                        cnt_state       <= '1';
                        source_node     <= to_integer(unsigned(DATA)); -- value of the source node
                        target_node     <= to_integer(unsigned(DATA)); -- value of the destination node
                    else
                        cnt_state       <= '0';
                    end if;
                    
                    COMPLETE            <= '0';
                    
                    VISITED             <= std_logic_vector(to_unsigned(0,VALUE_WIDTH));     
                
                when '1'=>
                    
                    traverse_en         <= '1';                 -- traverse process enable signal
                   
                    -- Checking if the destination is reached
                    if (visited_node=target_node) then
                        COMPLETE        <= '1';                 -- traverse completed signal
                        cnt_state       <= '0';
                    else
                        COMPLETE        <= '0';
                        cnt_state       <= '1';
                    end if; 
                    
                    VISITED             <= std_logic_vector(to_unsigned(visited_node,VALUE_WIDTH));     -- visited node 
                    
                    source_index        <= node_val_map(source_node);                                   -- index of source node
                                   
                
                when others=> null; 
            end case;
        
        end if;        
    end if;
end process graph_traverse_controller;


-- Traversing over the graph --
graph_traverse:process(CLK) 
variable current_node: integer range 0 to MAX_NODE_NUM; 
begin

    if rising_edge(CLK) then
        
        if(traverse_en='1') then
        
            if (first_node = '0') then
                
                node_value      <= source_node;                         -- value of visited node
                index           <= source_index;                        -- index of visited_node
                traverse_type   <= '0';                                 -- traverse stack indicator - get visited node from adj list  
                adj_case        <= "00";                                -- stack adjacencies of the source node  
                adj_num         <= node_adj_num(source_index);          -- adjacent node number of visited node
                register_en     <= '1';                                 -- register visited node enable signal
                stack_en        <= '1';                                 -- stack process enable signal
                first_node      <= '1';                                 -- source node / first visited node indicator 
                latency_cycle   <= '0';                                 -- latency cycle indicator

            else
            
                -- Checking adjacency status of the node
                if ( node_adj_num(index) = 0 ) then -- no adjacent node
                 
                    if ( latency_cycle = '0') then
                        traverse_type   <= '1';                         -- traverse stack indicator  - get visited node from stack   
                        adj_case        <= "10";                        -- shift stack
                        register_en     <= '1';                         -- register visited node enable signal
                        stack_en        <= '1';                         -- stack process enable signal
                        latency_cycle   <= '1';                         -- latency cycle indicator
                    else
                        index           <= node_val_map(stacked_node);  -- index of visited node
                        stacked_node    <= stack(1);                    -- stacked node
                        register_en     <= '0';                         -- register visited node disable signal
                        stack_en        <= '0';                         -- stack process disable signal           
                        latency_cycle   <= '0';                         -- latency cycle indicator
                        traverse_type   <= '0';                         -- traverse stack indicator 
                        adj_case        <= "11";                        -- stack null operation
                    end if;
                    
                else -- has adjacent node/nodes
                
                    -- Getting the first adjacent of the node as a visited node
                    current_node    := node_adj( index, 0 );            -- first adjacent node
                    node_value      <= current_node;                    -- value of visited node
                    index           <= node_val_map(current_node);      -- index of visited node
                    traverse_type   <= '0';                             -- traverse stack indicator - get visited node from adj list 
                    adj_case        <= "01";                            -- stack adjacencies of the node 
                    stacked_node    <= node_adj( index, 1 );            -- stacked node
                    register_en     <= '1';                             -- register visited node enable signal
                    stack_en        <= '1';                             -- stack process enable signal
                    latency_cycle   <= '0';                             -- latency cycle indicator
                    
                end if;
                
                adj_num             <= node_adj_num(index);             -- adjacent node number of the visited node
            end if;
    
    
            first_node      <= '1';                                     -- source node / first visited node indicator 
            
        else
            first_node      <= '0';
            register_en     <= '0';
            stack_en        <= '0';
            latency_cycle   <= '0'; 
            adj_case        <= "11";
            
        end if;        
    
    end if;
end process graph_traverse;


-- Registering visited node --
visited_node_register:process(CLK) 
begin

    if rising_edge(CLK) then
        
        if(register_en='1') then
        
            if (traverse_type = '0') then
                
                -- Registering visited node
                visited_node    <= node_value;  -- visited node
      
            else
            
               -- Registering the first element in the stack 
                visited_node    <= stack(0);    -- visited node
                
            end if;
          
        else
        
            visited_node    <= 0;
            
        end if;        
    
    end if;
end process visited_node_register;


--  Stacking adjacent nodes of visited node --
stack_nodes:process(CLK) 
begin

    if rising_edge(CLK) then
        
        if(stack_en='1') then
        
            -- Stacking adjacent nodes for 3 possible cases 
            case (adj_case) is          
            
                when "00" =>    -- source node case
                
                    -- Stacking adjacent nodes of the source node
                    for i in 0 to MAX_NODE_NUM-2 loop     
                        if ( i < adj_num ) then
                            stack(i) <= node_adj( index, i );
                        end if;    
                    end loop;  
                
                
                when "01" =>    -- 1 or more adjacent nodes case
                
                    -- Shifting stack by the number of adjacencies of the visited node
                    for i in 3 to MAX_NODE_NUM-1 loop
                        if ( i > adj_num ) then
                            stack(i-2) <= stack(i-adj_num-1);
                        end if;
                    end loop;
    
                    -- Stacking adjacent nodes of the visited node
                    for i in 1 to MAX_NODE_NUM-2 loop     
                        if ( i < adj_num ) then
                            stack(i-1) <= node_adj( index, i );
                        end if;    
                    end loop;  
                
                
                when "10" =>    -- no adjacent node case
                
                    -- Shifting the stack (1 node)
                    for i in 0 to MAX_NODE_NUM-2 loop
                        stack(i) <= stack(i+1);
                    end loop;
                    stack(MAX_NODE_NUM-1) <= 0;     
                
                
                when others => null;
            
            end case;
     
        end if;        
    
    end if;
end process stack_nodes;


end behavioral;
